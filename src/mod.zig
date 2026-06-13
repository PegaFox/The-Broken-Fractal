const Self = @This();

const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;
const json = std.json;
const Io = std.Io;
const path = std.fs.path;
const Dir = Io.Dir;
const File = Io.File;

const directories = @import("directories.zig");
const input = @import("input.zig");
const tile = @import("tile.zig");
const Object = @import("object.zig");
const Level = @import("scenes/level.zig");

const lua = @import("zlua");
const luaUtil = @import("lua.zig");

name: []const u8,
version: std.SemanticVersion,

/// These get default values so json parsing doesn't complain about missing fields
tileStartType: tile.Type = undefined,
objectStartType: Object.Type = undefined,
levelStartID: Level.ID = undefined,

pub var mods = std.ArrayList(Self).empty;

pub fn findTileMod(tileType: tile.Type) *const Self
{
  return modBinarySearch("tileStartType", tileType);
}

pub fn findObjectMod(objectType: Object.Type) *const Self
{
  return modBinarySearch("objectStartType", objectType);
}

pub fn findLevelMod(levelID: Level.ID) *const Self
{
  return modBinarySearch("levelStartID", levelID);
}

pub const Identifier = struct
{
  mod: []const u8,
  name: []const u8,

  pub const HashContext = struct
  {
    pub fn hash(self: @This(), value: Identifier) u64
    {
      _ = self;

      return std.hash_map.getAutoHashFn([2]u64, void)(
        undefined,
        .{
          std.hash_map.hashString(value.mod),
          std.hash_map.hashString(value.name),
        });
    }
    pub fn eql(self: @This(), a: Identifier, b: Identifier) bool
    {_ = self;

      return
        std.hash_map.eqlString(a.mod, b.mod) and
        std.hash_map.eqlString(a.name, b.name);
    }
  };
};

pub var luaEnv: ?*lua.Lua = null;

pub fn reloadAll(io: Io, allocator: Allocator) !void
{
  try unloadAll(io, null);
  try loadAll(io, allocator);
}

pub fn reload(name: []const u8) void
{
  unload(name);
  load(name);
}

pub fn loadAll(io: Io, allocator: Allocator) !void
{
  // Just in case one of the last mods fail to load
  errdefer unloadAll(allocator, false);

  var it = try DirIterator.init(io);
  defer it.deinit(io);
  while (try it.next(io)) |mod|
  {
    try load(io, allocator, mod);
  }
}

/// If retainMemory == false, allocated mod memory is freed
pub fn unloadAll(allocator: Allocator, retainMemory: bool) void
{
  // unload uses swapRemove, so we remove this way to avoid ordering issues
  while (mods.items.len > 0)
  {
    mods.items[mods.items.len-1].unload(allocator);
  }

  if (!retainMemory)
  {
    tile.staticData.clearAndFree(allocator);
    tile.nameTypes.clearAndFree(allocator);
    Level.levels.clearAndFree(allocator);
    Level.nameIDs.clearAndFree(allocator);
    mods.clearAndFree(allocator);

    if (luaEnv) |env|
    {
      env.deinit();
      luaEnv = null;
    }
  }
}

const LoadError = error
{
  NoInfoJson,
} ||
json.ParseError(json.Reader) ||
Allocator.Error ||
error{
  LuaError,
  LuaSyntax,
  OutOfMemory,
  LuaRuntime,
  LuaMsgHandler,
  LuaGCMetaMethod,
  LuaGlobalContamination
};

//const JsonColor = struct
//{
//  r: f32,
//  g: f32,
//  b: f32,
//};
//
//const JsonTileData = blk:{ 
//  const Type = std.builtin.Type;
//
//  const tileDataInfo = @typeInfo(tile.StaticData).@"struct";
//
//  var fieldNames: [tileDataInfo.fields.len][]const u8 = undefined;
//  var fieldTypes: [tileDataInfo.fields.len]type = undefined;
//  var fieldAttrs: [tileDataInfo.fields.len]Type.StructField.Attributes =
//    undefined;
//
//  for (0.., tileDataInfo.fields) |f, field|
//  {
//    fieldNames[f] = field.name;
//    if (std.mem.eql(u8, field.name, "color"))
//    {
//      fieldTypes[f] = JsonColor;
//    } else if (std.mem.eql(u8, field.name, "ch"))
//    {
//      fieldTypes[f] = []const u8;
//    } else
//    {
//      fieldTypes[f] = field.type;
//    }
//
//    fieldAttrs[f] = .{};
//  }
//  
//  break:blk @Struct(
//    tileDataInfo.layout,
//    tileDataInfo.backing_integer,
//    &fieldNames,
//    &fieldTypes,
//    &fieldAttrs,
//  );
//};

/// Does not close modDir
pub fn load(io: Io, allocator: Allocator, modDir: Dir) LoadError!void
{
  if (luaEnv == null)
  {
    luaEnv = try luaUtil.init(allocator);
  }

  const luaGlobalCount = luaUtil.globalCount(luaEnv.?);

  try loadInit(io, allocator, modDir);

  // The current mod's table is at the top of the stack
  _ = luaEnv.?.pushString(mods.getLast().name);
  std.debug.assert(luaEnv.?.getTable(-2) == .table);
  defer luaEnv.?.pop(2); // Clear the mod tables from the stack

  try loadInputs(io, allocator, modDir);

  try loadTiles(io, allocator, modDir);

  try loadActions(io, allocator, modDir);

  try loadObjects(io, allocator, modDir);

  try loadLevels(io, allocator, modDir);

  const globalsAdded: i32 =
    @as(i32, @intCast(luaUtil.globalCount(luaEnv.?))) -
    @as(i32, @intCast(luaGlobalCount));
  if (globalsAdded > 0)
  {
    log.err(
      "Global variables must not be added by mods, {} added\n",
      .{globalsAdded}
    );
    return LoadError.LuaGlobalContamination;
  } else if (globalsAdded < 0)
  {
    log.err(
      "Global variables must not be removed by mods, {} removed\n",
      .{-globalsAdded}
    );
    return LoadError.LuaGlobalContamination;
  }
}

pub fn unload(mod: *Self, allocator: Allocator) void
{
  const modIndex = mod - mods.items.ptr;

  const afterLastTileType = if (modIndex < mods.items.len-1)
    mods.items[modIndex+1].tileStartType
  else
    tile.staticData.items.len;

  for (tile.staticData.items[
    mod.tileStartType..afterLastTileType
  ]) |*modTile|
  {
    std.debug.assert(
      tile.nameTypes.remove(.{.mod = mod.name, .name = modTile.name})
    );

    allocator.free(modTile.name);
    modTile.* = undefined;
  }

  const afterLastLevelID = if (modIndex < mods.items.len-1)
    mods.items[modIndex+1].levelStartID
  else
    Level.levels.items.len;

  for (Level.levels.items[
    mod.levelStartID..afterLastLevelID
  ]) |*modLevel|
  {
    std.debug.assert(
      Level.nameIDs.remove(.{.mod = mod.name, .name = modLevel.name})
    );

    allocator.free(modLevel.name);
    modLevel.* = undefined;
  }

  allocator.free(mod.name);
  _ = mods.swapRemove(mod - mods.items.ptr);
}

// This leaves the mod table at the top of the stack
fn loadInit(io: Io, allocator: Allocator, modDir: Dir) LoadError!void
{
  const infoFile = modDir.openFile(io, "info.json", .{}) catch
    return LoadError.NoInfoJson;
  const info = try jsonFromFile(Self, io, allocator, infoFile);
  try mods.append(allocator, .{
    .name = try allocator.dupe(u8, info.value.name),
    .version = info.value.version,
    .tileStartType = @intCast(tile.staticData.items.len),
    .levelStartID = @intCast(Level.levels.items.len),
  });
  info.deinit();
  infoFile.close(io);

  log.info("Loading mod {s}\n", .{mods.getLast().name});

  // Add an element to the mods table, reserving space for tiles, objects, levels, and version
  std.debug.assert(try luaEnv.?.getGlobal("fractal") == .table);
  std.debug.assert(luaEnv.?.getField(-1, "mods") == .table);
  _ = luaEnv.?.pushString(mods.getLast().name);
  try luaEnv.?.pushAny(
    struct
    {// Void slices to ensure empty tables
      inputs: []void,
      tiles: []void,
      actions: []void,
      objects: []void,
      levels: []void,
      version: std.SemanticVersion
    }{
      .inputs = &.{},
      .tiles = &.{},
      .actions = &.{},
      .objects = &.{},
      .levels = &.{},
      .version = mods.getLast().version
    }
  );
  luaEnv.?.setTable(-3);
  
  if (modDir.openFile(io, "init.lua", .{})) |initFile|
  {
    defer initFile.close(io);

    const name = try std.mem.concatWithSentinel(
      allocator, u8, &.{mods.getLast().name, ".init"}, 0
    );
    defer allocator.free(name);

    try luaUtil.runFile(luaEnv.?, io, initFile, name);
  } else |e|
  {
    log.warn("No init.lua found: {}, skipping\n", .{e});
  }
}

fn loadTiles(io: Io, allocator: Allocator, modDir: Dir) LoadError!void
{
  // At this point, the mod's table is at the top of the stack
  std.debug.assert(luaEnv.?.getSubtable(-1, "tiles"));
  defer luaEnv.?.pop(1);
  if (modDir.openDir(io, "tiles", .{.iterate = true})) |tileDir|
  {
    defer tileDir.close(io);

    var walker = try tileDir.walk(allocator);
    defer walker.deinit();
    while (walker.next(io) catch null) |entry|
    {
      if (entry.kind != .file)
      {
        continue;
      }

      if (!std.mem.eql(u8, path.extension(entry.basename), ".json"))
      {
        continue;
      }

      const tileFile = tileDir.openFile(io, entry.path, .{}) catch continue;
      defer tileFile.close(io);

      const tileInfo =
        try jsonFromFile(tile.StaticData, io, allocator, tileFile);
      defer tileInfo.deinit();

      log.info("Loading tile {s}\n", .{tileInfo.value.name});

      try tile.staticData.append(allocator, .{
        .name = try allocator.dupe(u8, tileInfo.value.name),
        .walkable = tileInfo.value.walkable,
        .color = tileInfo.value.color,
        .wallConnect = tileInfo.value.wallConnect,
        .ch = tileInfo.value.ch,
      });
      try tile.nameTypes.putNoClobber(
        allocator,
        .{.mod = mods.getLast().name, .name = tile.staticData.getLast().name},
        @intCast(tile.staticData.items.len-1)
      );

      const data = tile.staticData.getLast();
      _ = luaEnv.?.pushString(data.name);
      try luaEnv.?.pushAny(
        struct
        {
          walkable: bool,
          color: struct {r: f32, g: f32, b: f32},
          wallConnect: bool,
          ch: []const u8
        }{
          .walkable = data.walkable,
          .color = .{
            .r = data.color[0],
            .g = data.color[1],
            .b = data.color[2]
          },
          .wallConnect = tile.staticData.getLast().wallConnect,
          .ch = (&tile.staticData.getLast().ch)[0..1],
        }
      );
      luaEnv.?.setTable(-3);

    }
  } else |e|
  {
    log.warn("No tiles directory found: {}, skipping\n", .{e});
  }
}

fn loadInputs(io: Io, allocator: Allocator, modDir: Dir) LoadError!void
{
  // At this point, the mod's table is at the top of the stack
  std.debug.assert(luaEnv.?.getSubtable(-1, "inputs"));
  defer luaEnv.?.pop(1);
  if (modDir.openFile(io, "inputs.json", .{})) |inputFile|
  {
    defer inputFile.close(io);

    const inputs =
      try jsonFromFile(
        []struct
        {
          name: []const u8,
          defaultBinds: []struct {key: [:0]const u8},
        },
        io,
        allocator,
        inputFile
      );
    defer inputs.deinit();

    log.info("Loading inputs\n", .{});

    try input.bindings.ensureUnusedCapacity(allocator, 20);
    for (inputs.value) |in|
    {
      const startIndex: input.IndexBinding = @intCast(input.bindings.items.len);

      for (in.defaultBinds) |binding|
      {
        const keyCode = input.keyFromString(binding.key) catch |e|
        {
          log.err("Failed to get key \'{s}\': {}\n", .{binding.key, e});
          continue;
        };

        try input.bindings.append(allocator, keyCode);

        try input.bindings.append(allocator, 0);
      }

      try input.inputs.put(
        allocator,
        startIndex,
        try allocator.dupe(u8, in.name),
      );
      //try Object.nameTypes.putNoClobber(
      //  allocator,
      //  .{.mod = mods.getLast().name, .name = tile.staticData.getLast().name},
      //  @intCast(tile.staticData.items.len-1)
      //);
      
      _ = luaEnv.?.pushString(in.name);
      luaEnv.?.pushValue(-1);
      luaEnv.?.setTable(-3);
    }
  } else |e|
  {
    log.warn("No inputs.json found: {}, skipping\n", .{e});
  }
}

fn loadActions(io: Io, allocator: Allocator, modDir: Dir) LoadError!void
{
  // At this point, the mod's table is at the top of the stack
  std.debug.assert(luaEnv.?.getSubtable(-1, "actions"));
  defer luaEnv.?.pop(1);
  if (modDir.openDir(io, "actions", .{.iterate = true})) |actionDir|
  {
    defer actionDir.close(io);

    var walker = try actionDir.walk(allocator);
    defer walker.deinit();
    while (walker.next(io) catch null) |entry|
    {
      if (entry.kind != .file)
      {
        continue;
      }

      if (!std.mem.eql(u8, path.extension(entry.basename), ".json"))
      {
        continue;
      }

      const actionFile = actionDir.openFile(io, entry.path, .{}) catch continue;
      defer actionFile.close(io);

      const actionInfo =
        try jsonFromFile(struct {name: []const u8}, io, allocator, actionFile);
      defer actionInfo.deinit();

      log.info("Loading action {s}\n", .{actionInfo.value.name});

      //try Object.staticData.append(allocator, .{
      //  .name = try allocator.dupe(u8, actionInfo.value.name),
      //  .ch = actionInfo.value.ch,
      //  .color = actionInfo.value.color,
      //});
      //try Object.nameTypes.putNoClobber(
      //  allocator,
      //  .{.mod = mods.getLast().name, .name = tile.staticData.getLast().name},
      //  @intCast(tile.staticData.items.len-1)
      //);

      _ = luaEnv.?.pushString(actionInfo.value.name);
      luaEnv.?.createTable(0, 1);
      const luaFilePath = try std.mem.concat(
        allocator, u8, &.{entry.path[0..entry.path.len-4], "lua"}
      );
      defer allocator.free(luaFilePath);
      if (actionDir.openFile(io, luaFilePath, .{})) |luaFile|
      {
        const name = try std.mem.concatWithSentinel(
          allocator, u8, &.{mods.getLast().name, ".", actionInfo.value.name}, 0
        );
        defer allocator.free(name);

        try luaUtil.runFile(luaEnv.?, io, luaFile, name);

        inline for (.{
          "queue",
        }) |functionName|
        {
          if (luaEnv.?.getGlobal(functionName)) |t|
          {
            std.debug.assert(t == .function);

            luaEnv.?.setField(-2, functionName);

            luaEnv.?.pushNil();
            luaEnv.?.setGlobal(functionName);
          } else |e|
          {
            luaEnv.?.pop(1);

            log.warn(
              "No " ++ functionName ++ " function found for action {s}: {}, skipping\n",
              .{actionInfo.value.name, e}
            );
          }
        }
      } else |e|
      {
        log.warn(
          "No lua file found for action {s}: {}, skipping\n",
          .{actionInfo.value.name, e}
        );
      }
      luaEnv.?.setTable(-3);
    }
  } else |e|
  {
    log.warn("No actions directory found: {}, skipping\n", .{e});
  }
}

fn loadObjects(io: Io, allocator: Allocator, modDir: Dir) LoadError!void
{
  // At this point, the mod's table is at the top of the stack
  std.debug.assert(luaEnv.?.getSubtable(-1, "objects"));
  defer luaEnv.?.pop(1);
  if (modDir.openDir(io, "objects", .{.iterate = true})) |objectDir|
  {
    defer objectDir.close(io);

    var walker = try objectDir.walk(allocator);
    defer walker.deinit();
    while (walker.next(io) catch null) |entry|
    {
      if (entry.kind != .file)
      {
        continue;
      }

      if (!std.mem.eql(u8, path.extension(entry.basename), ".json"))
      {
        continue;
      }

      const objectFile = objectDir.openFile(io, entry.path, .{}) catch continue;
      defer objectFile.close(io);

      const objectInfo =
        try jsonFromFile(Object.StaticData, io, allocator, objectFile);
      defer objectInfo.deinit();

      log.info("Loading object {s}\n", .{objectInfo.value.name});

      try Object.staticData.append(allocator, .{
        .name = try allocator.dupe(u8, objectInfo.value.name),
        .ch = objectInfo.value.ch,
        .color = objectInfo.value.color,
      });
      try Object.nameTypes.putNoClobber(
        allocator,
        .{.mod = mods.getLast().name, .name = tile.staticData.getLast().name},
        @intCast(tile.staticData.items.len-1)
      );

      const data = Object.staticData.getLast();
      _ = luaEnv.?.pushString(data.name);
      try luaEnv.?.pushAny(
        struct
        {
          color: struct {r: f32, g: f32, b: f32},
          ch: []const u8
        }{
          .color = .{
            .r = data.color[0],
            .g = data.color[1],
            .b = data.color[2]
          },
          .ch = (&tile.staticData.getLast().ch)[0..1],
        }
      );

      // Copy mod table reference
      luaEnv.?.pushValue(-4);
      luaEnv.?.setField(-2, "mod");

      const luaFilePath = try std.mem.concat(
        allocator, u8, &.{entry.path[0..entry.path.len-4], "lua"}
      );
      defer allocator.free(luaFilePath);
      if (objectDir.openFile(io, luaFilePath, .{})) |luaFile|
      {
        const name = try std.mem.concatWithSentinel(
          allocator, u8, &.{mods.getLast().name, ".", objectInfo.value.name}, 0
        );
        defer allocator.free(name);

        try luaUtil.runFile(luaEnv.?, io, luaFile, name);

        inline for (.{
          "takeTurn",
        }) |functionName|
        {
          if (luaEnv.?.getGlobal(functionName)) |t|
          {
            std.debug.assert(t == .function);

            luaEnv.?.setField(-2, functionName);

            luaEnv.?.pushNil();
            luaEnv.?.setGlobal(functionName);
          } else |e|
          {
            luaEnv.?.pop(1);

            log.warn(
              "No " ++ functionName ++ " function found for object {s}: {}, skipping\n",
              .{objectInfo.value.name, e}
            );
          }
        }
      } else |e|
      {
        log.warn(
          "No lua file found for object {s}: {}, skipping\n",
          .{objectInfo.value.name, e}
        );
      }
      luaEnv.?.setTable(-3);
    }
  } else |e|
  {
    log.warn("No objects directory found: {}, skipping\n", .{e});
  }
}

fn loadLevels(io: Io, allocator: Allocator, modDir: Dir) LoadError!void
{
  // At this point, the mod's table is at the top of the stack
  std.debug.assert(luaEnv.?.getSubtable(-1, "levels"));
  defer luaEnv.?.pop(1);
  if (modDir.openDir(io, "levels", .{.iterate = true})) |levelDir|
  {
    defer levelDir.close(io);

    var walker = try levelDir.walk(allocator);
    defer walker.deinit();
    while (walker.next(io) catch null) |entry|
    {
      if (entry.kind != .file)
      {
        continue;
      }

      if (!std.mem.eql(u8, path.extension(entry.basename), ".json"))
      {
        continue;
      }

      const infoFile =
        levelDir.openFile(io, entry.path, .{}) catch continue;
      defer infoFile.close(io);

      const levelInfo = try jsonFromFile(
        struct {name: []const u8}, io, allocator, infoFile
      );
      defer levelInfo.deinit();

      log.info("Loading level {s}\n", .{levelInfo.value.name});

      try Level.levels.append(allocator, .{
        .name = try allocator.dupe(u8, levelInfo.value.name),
        .camPos = @splat(0),
        .tiles = .empty,
      });
      try Level.nameIDs.putNoClobber(
        allocator,
        .{
          .mod = mods.getLast().name,
          .name = Level.levels.getLast().name
        },
        @intCast(tile.staticData.items.len-1)
      );

      const luaFilePath = try std.mem.concat(
        allocator, u8, &.{entry.path[0..entry.path.len-4], "lua"}
      );
      defer allocator.free(luaFilePath);
      if (levelDir.openFile(io, luaFilePath, .{})) |luaFile|
      {
        const name = try std.mem.concatWithSentinel(
          allocator, u8, &.{mods.getLast().name, ".", levelInfo.value.name}, 0
        );
        defer allocator.free(name);

        try luaUtil.runFile(luaEnv.?, io, luaFile, name);

        _ = luaEnv.?.pushString(levelInfo.value.name);
        luaEnv.?.createTable(0, 10);

        // Levels are unique, so light userdata (a pointer) is probably best for them
        // I cannot express the pain I feel at this statement
        @setRuntimeSafety(false);
        luaEnv.?.pushLightUserdata(@ptrFromInt(Level.levels.items.len-1));
        luaEnv.?.setField(-2, "handle");

        pushLevelSubNamespace(
          "tiles",
          .{
            .get = luaUtil.luaTile.get,
            .getInfo = luaUtil.luaTile.getInfo,
            .count = luaUtil.luaTile.count,
            .iterate = luaUtil.luaTile.iterate,
            .remove = luaUtil.luaTile.remove,
          }
        ) catch unreachable;

        pushLevelSubNamespace(
          "camera",
          .{
            .setPos = luaUtil.luaCamera.setPos,
            .center = luaUtil.luaCamera.center,
            .centerOn = luaUtil.luaCamera.centerOn,
          }
        ) catch unreachable;

        pushLevelSubNamespace(
          "objects",
          .{
            .get = luaUtil.luaObject.get,
          }
        ) catch unreachable;

        inline for (.{
          "init",
          "deinit",
          "enter",
          "exit",
          "update",
          "generateTile",
        }) |functionName|
        {
          if (luaEnv.?.getGlobal(functionName)) |t|
          {
            std.debug.assert(t == .function);

            luaEnv.?.setField(-2, functionName);

            luaEnv.?.pushNil();
            luaEnv.?.setGlobal(functionName);
          } else |e|
          {
            luaEnv.?.pop(1);

            log.warn(
              "No " ++ functionName ++ " function found for level {s}: {}, skipping\n",
              .{levelInfo.value.name, e}
            );
          }
        }

        luaEnv.?.setTable(-3);
      } else |e|
      {
        log.warn(
          "No lua file found for level {s}: {}, skipping\n",
          .{levelInfo.value.name, e}
        );
      }
      //const data = tile.staticData.getLast();
      //_ = luaEnv.?.pushString(data.name);
      //try luaEnv.?.pushAny(
      //  struct
      //  {
      //    walkable: bool,
      //    color: struct {r: f32, g: f32, b: f32},
      //    wallConnect: bool,
      //    ch: []const u8
      //  }{
      //    .walkable = data.walkable,
      //    .color = .{
      //      .r = data.color[0],
      //      .g = data.color[1],
      //      .b = data.color[2]
      //    },
      //    .wallConnect = tile.staticData.getLast().wallConnect,
      //    .ch = (&tile.staticData.getLast().ch)[0..1],
      //  }
      //);
      //luaEnv.?.setTable(-3);

    }
  } else |e|
  {
    log.warn("No tiles directory found: {}, skipping\n", .{e});
  }
}

/// Takes in a namespace name and a struct of functions
/// Stores the namespace table at luaStackTopTable[name]
/// Assumes that the level table is on top of the lua stack
fn pushLevelSubNamespace(name: [:0]const u8, functions: anytype)
  error{NotAStruct}!void
{
  const fieldInfo = switch (@typeInfo(@TypeOf(functions))) {
    .@"struct" => |info| info,
    else => return error.NotAStruct
  };

  luaEnv.?.createTable(0, fieldInfo.fields.len+1);
  luaEnv.?.pushValue(-2);
  luaEnv.?.setField(-2, "parent");

  inline for (fieldInfo.fields) |field|
  {
    luaEnv.?.pushFunction(@field(functions, field.name));
    luaEnv.?.setField(-2, field.name);
  }

  luaEnv.?.setField(-2, name);
}

/// Iterates through the mods directory
const DirIterator = struct
{
  rootDir: Dir,
  it: Dir.Iterator,
  currentDir: ?Dir,
 
  pub fn init(io: Io) !@This()
  {
    const modsDir = try directories.getDir(io, &.{"mods"});
    return .{
      .rootDir = modsDir,
      .it = modsDir.iterateAssumeFirstIteration(),
      .currentDir = null,
    };
  }

  pub fn deinit(self: @This(), io: Io) void
  {
    if (self.currentDir) |dir|
    {
      dir.close(io);
    }

    self.rootDir.close(io);
  }

  /// Returned directory is valid until next call or deinit()
  pub fn next(self: *@This(), io: Io) !?Dir
  {
    if (self.currentDir) |dir|
    {
      dir.close(io);
      self.currentDir = null;
    }

    const entry = (self.it.next(io) catch return null) orelse return null;

    self.currentDir = switch (entry.kind)
    {
      .directory => try self.rootDir.openDir(io, entry.name, .{}),
      //.sym_link,
      .file => dir:{
        const zipFile = try self.rootDir.openFile(io, entry.name, .{});
        var readerBuffer: [1024]u8 = undefined;
        var zipFileReader = zipFile.reader(io, &readerBuffer);

        const resultDir = try directories.getDir(io, &.{"cache"});
        defer resultDir.close(io);

        try resultDir.deleteTree(io, path.stem(entry.name));
        try std.zip.extract(resultDir, &zipFileReader, .{});

        break:dir try resultDir.openDir(io, path.stem(entry.name), .{});
      },
      else => try self.next(io),
    };

    return self.currentDir;
  }
};

fn jsonFromFile(comptime T: type, io: Io, allocator: Allocator, jsonFile: File)
  json.ParseError(json.Reader)!json.Parsed(T)
{
  var readBuffer: [128]u8 = undefined;
  var reader = jsonFile.reader(io, &readBuffer);
  var jsonReader =
    std.json.Reader.init(allocator, &reader.interface);
  defer jsonReader.deinit();

  return try std.json.parseFromTokenSource(
    T, allocator, &jsonReader, .{.ignore_unknown_fields = true}
  );
}

/// This will need to be replaced if the mods array is no longer in ID order
fn modBinarySearch(
  comptime field: []const u8,
  id: @TypeOf(@field(@as(Self, undefined), field))) *const Self
{
  const index = std.sort.upperBound(
    Self,
    mods.items,
    id,
    struct {fn compare(context: @TypeOf(id), mod: Self) std.math.Order
    {
      return
        if (context > @field(mod, field)) .gt
        else if (context < @field(mod, field)) .lt
        else .eq;
    }}.compare
  );

  if (index == mods.items.len)
  {
    return &mods.items[0];
  } else
  {
    return &mods.items[index];
  }
}

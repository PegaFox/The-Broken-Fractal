const Self = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const File = Io.File;
const log = std.log;

const ECS = @import("ecs");
const graphics = @import("graphics.zig");
const Mod = @import("mod.zig");
const Sight = @import("sight.zig");
const Level = @import("scenes/level.zig");
const tile = @import("tile.zig");
const mainspace = @import("main.zig");
const lua = @import("zlua");

pub fn init(allocator: Allocator) Allocator.Error!*lua.Lua
{
  const state = try lua.Lua.init(allocator);

  state.openBase();

  state.pushFunction(lua.wrap(luaPrint));
  state.setGlobal("print");

  // This function seems a little dangerous for strangers, so I'm removing it
  state.pushNil();
  state.setGlobal("collectgarbage");

  state.openCoroutine();
  state.openString();
  state.openUtf8();
  state.openTable();
  state.openMath();

  state.openOS(); // Oh, brother

  // In case OS failed to load
  if (state.getGlobal("os")) |osType|
  {
    std.debug.assert(osType == .table);

    state.pushNil();
    state.setField(-2, "execute");
    state.pushNil();
    state.setField(-2, "exit");
    state.pushNil();
    state.setField(-2, "remove");
    state.pushNil();
    state.setField(-2, "rename");
    state.pushNil();
    state.setField(-2, "tmpname");
    //state.setGlobal("os");
    state.pop(1);
  } else |_| {}

  // 8 is an approximation and it may be smart to check enabled mod count and use that instead
  state.createTable(0, 8);
  state.setGlobal("mods");

  return state;
}

pub fn runFile(self: *lua.Lua, io: Io, file: File, name: [:0]const u8)
  error{LuaSyntax, OutOfMemory, LuaRuntime, LuaMsgHandler, LuaGCMetaMethod}!void
{
  try loadFile(self, io, file, name);

  try runFunction(self);
}

pub fn loadFile(self: *lua.Lua, io: Io, file: File, name: [:0]const u8)
  error{LuaSyntax, OutOfMemory, LuaRuntime, LuaMsgHandler}!void
{
  const chunkSize = 256;

  var readerData = struct
  {
    io: Io,
    file: File,
    buffer: [chunkSize]u8,
    position: usize,
  }{
    .io = io,
    .file = file,
    .buffer = undefined,
    .position = 0,
  };
  //var luaReader = luaFile.reader(io, &luaReadBuffer);
  //luaReader.interface.readSliceShort();

  const readFn = struct {fn read(
    L: ?*lua.LuaState,
    selfReader: ?*anyopaque,
    size: [*c]usize) callconv(.c) [*c]const u8
  {_ = L;
    const selfData: *@TypeOf(readerData) = @ptrCast(@alignCast(selfReader));

    size.* = selfData.file.readPositionalAll(
      selfData.io, &selfData.buffer, selfData.position
    ) catch return null;
    selfData.position += size.*;

    return &selfData.buffer;
  }}.read;

  //pub const CReaderFn = *const fn (state: ?*LuaState, data: ?*anyopaque, size: [*c]usize) callconv(.c) [*c]const u8;
  //fn load52(lua: *Lua, reader: CReaderFn, data: *anyopaque, chunk_name: [:0]const u8, mode: Mode) LoadError!void {
  try self.load(
    readFn, &readerData, name, .binary_text
  );
}

/// Logs an error if the function fails
pub fn runFunction(self: *lua.Lua)
  error{LuaSyntax, OutOfMemory, LuaRuntime, LuaMsgHandler, LuaGCMetaMethod}!void
{
  self.protectedCall(.{}) catch |e|
  {
    // TYpes are commented out if I can't think of a good way to log them
    switch (self.typeOf(-1))
    {
      .nil => log.err(
        "Lua error\n", .{}
      ),
      .boolean => log.err(
        "Lua error: {}\n", .{self.toBoolean(-1)}
      ),
      //.light_userdata => log.err(
      //  "Lua error: {}\n", .{}
      //),
      .number => log.err(
        "Lua error: {}\n", .{self.toNumber(-1) catch unreachable}
      ),
      .string => log.err(
        "Lua error: {s}\n", .{self.toString(-1) catch unreachable}
      ),
      //.table => log.err(
      //  "Lua error: {}\n", .{}
      //),
      //.function => log.err(
      //  "Lua error: {}\n", .{}
      //),
      //.userdata => log.err(
      //  "Lua error: {}\n", .{}
      //),
      //.thread => log.err(
      //  "Lua error: {}\n", .{}
      //),
      else => {}
    }

    self.pop(1);
    return e;
  };
}

/// O(N) time complexity
pub fn globalCount(self: *lua.Lua) usize
{
  var count: u32 = 0;

  self.pushGlobalTable();
  self.pushNil();
  while (self.next(-2))
  {
    count += 1;
    self.pop(1);
  }
  self.pop(1);

  return count;
}

fn luaPrint(self: *lua.Lua) i32
{
  const argNum = @max(0, self.getTop());

  self.checkStackErr(1, null);

  for (1..argNum+1) |arg|
  {
    const string = self.toStringEx(@intCast(arg));
    log.info("{s}", .{string});
    self.pop(1);
  }

  log.info("\n", .{});
  
  return 0;
}

/// self:tileGet(pos) => {"mod", "name"}
pub fn luaTileGet(state: ?*lua.LuaState) callconv(.c) c_int
{
  const self: *lua.Lua = @ptrCast(state orelse unreachable);

  const args = getLuaLevelPosArgs(self);

  const tileEntity =
    Level.levels.items[args.levelID].getTile(args.pos) catch return 0;
  const tileType =
    mainspace.ecs.get(tileEntity, "tileType", tile.Type) orelse unreachable;

  self.createTable(2, 0);

  _ = self.pushString(Mod.findTileMod(tileType).name);
  self.setIndex(-2, 1);

  _ = self.pushString(tile.staticData.items[tileType].name);
  self.setIndex(-2, 2);

  return 1;
}

/// self:tileGetInfo(pos) => {
///   name = "cyanideCarpet",
///   walkable = true,
///   color = {"r": 1.0, "g": 1.0, "b": 1.0},
///   wallConnect = false,
///   ch = "."
/// } or nil
/// This is slightly faster than calling luaTileGet then accessing it using the global table
pub fn luaTileGetInfo(state: ?*lua.LuaState) callconv(.c) c_int
{
  const self: *lua.Lua = @ptrCast(state orelse unreachable);

  const args = getLuaLevelPosArgs(self);

  const tileEntity =
    Level.levels.items[args.levelID].getTile(args.pos) catch return 0;
  const data = tile.getStaticData(tileEntity) orelse return 0;

  self.pushAny(
    struct
    {
      name: []const u8,
      walkable: bool,
      color: struct {r: f32, g: f32, b: f32},
      wallConnect: bool,
      ch: []const u8
    }{
      .name = data.name,
      .walkable = data.walkable,
      .color = .{
        .r = data.color[0],
        .g = data.color[1],
        .b = data.color[2]
      },
      .wallConnect = data.wallConnect,
      .ch = (&data.ch)[0..1],
    }
  ) catch return 0;

  return 1;
}

/// self.tile:iterate() => iterator
/// Used with for loops to iterate over a level's tiles
pub const luaTileIterate = lua.wrap(luaTileIterateInner);

fn luaTileIterateInner(state: *lua.Lua) i32
{
  // This should be table, but it fails to compile unless the comparison is for .light_userdata
  state.argCheck(state.getField(1, "parent") == .table, 1, "Not a namespace");
  state.argCheck(
    state.getField(-1, "handle") == .light_userdata,
    1,
    "Not a level"
  );

  state.pushValue(1);
  // Store current index as closure
  state.pushInteger(0);
  state.pushClosure(lua.wrap(
    struct {fn nextTile(self: *lua.Lua) c_int
      //error{NotANamespace, NotALevel}!
      //?struct {Level.Coord, ECS.Entity.Unmanaged}
    {
      const levelId: Level.ID =
        if (self.toUserdata(anyopaque, -1)) |id| @intCast(@intFromPtr(id))
        else |_| 0;

      const index = self.toInteger(lua.Lua.upvalueIndex(2)) catch unreachable;
      self.pushInteger(index + 1);
      self.replace(lua.Lua.upvalueIndex(2));

      const tiles = &Level.levels.items[levelId].tiles;

      if (index < tiles.count())
      {
        // The catch unreachable here may be incorrect if the key type is changed, so we assert the type here
        std.debug.assert(@TypeOf(tiles.keys()[@intCast(index)]) == Level.Coord);
        self.pushAny(tiles.keys()[@intCast(index)]) catch unreachable;
        self.pushInteger(tiles.values()[@intCast(index)]);
        return 2;
      } else 
      {
        return 0;
      }
    }}.nextTile), 2);

  return 1;
}

/// self:tileRemove(pos) => bool
/// Removes tile at pos
/// Returns whether there was a tile there
pub const luaTileRemove = toApiFunction(
  "tileRemove",
  luaTileRemoveInner,
  .{}
) catch unreachable;

fn luaTileRemoveInner(level: LevelHandle, pos: Level.Coord) bool
{
  return Level.levels.items[@intFromPtr(level.id)].tiles.swapRemove(pos);
}

/// self:tileCount() => int
/// Returns size of level's tilemap
pub const luaTileCount = toApiFunction(
  "tileCount",
  luaTileCountInner,
  .{}
) catch unreachable;

fn luaTileCountInner(level: LevelHandle) u32
{
  return @intCast(Level.levels.items[@intFromPtr(level.id)].tiles.count());
}

/// self.objects:get(index) or
/// self.objects:get(pos) or
/// self.objects.get(index) => {
///   id: ECS.Entity.Unmanaged,
///   if hasComponent(sight) sight
/// }
pub fn luaObjectGet(state: ?*lua.LuaState) callconv(.c) c_int
{
  const self: *lua.Lua = @ptrCast(state orelse unreachable);

  if (self.getTop() == 1)
  {
    self.argExpected(self.isInteger(1), 1, "index");
    const index = self.toInteger(1) catch unreachable;
    self.argCheck(
      index >= 0 and index < Level.objects.items.len,
      1,
      "Index out of range"
    );

    luaGenerateObject(
      self,
      .{.parent = &mainspace.ecs, .id = Level.objects.items[@intCast(index)].id}
    );

    return 1;
  } else if (self.getTop() > 1)
  {
    if (self.isInteger(2))
    {
      const index = self.toInteger(2) catch unreachable;
      self.argCheck(
        index >= 0 and index < Level.objects.items.len,
        1,
        "Index out of range"
      );

      luaGenerateObject(
        self,
        .{
          .parent = &mainspace.ecs,
          .id = Level.objects.items[@intCast(index)].id
        }
      );

      return 1;
    } else
    {
      // TODO: This
    }
  }

  return 0;
}

/// Pushes an object table with the object's components onto the lua stack
/// Does not verify stack space
pub fn luaGenerateObject(state: *lua.Lua, object: ECS.Entity.Managed) void
{
  state.createTable(0, 2);
  state.pushInteger(object.id);
  state.setField(-2, "id");

  if (object.get("sight", Sight)) |_|
  {
    state.createTable(0, 1);

    state.pushValue(-2);
    state.pushClosure(toApiFunction(
      "object.sight.inView",
      struct {fn inView(self: *lua.Lua, pos: Level.Coord) !bool
      {
        std.debug.assert(
          self.getField(lua.Lua.upvalueIndex(1), "id") == .number
        );
        const objectId: ECS.Entity.Managed = .{
          .parent = &mainspace.ecs,
          .id = @intCast(try self.toInteger(-1)),
        };

        const sight = objectId.get("sight", Sight) orelse
          return error.InvalidComponent;

        return sight.inView(pos);
      }}.inView, .{}
    ) catch unreachable, 1);
    
    state.setField(-2, "inView");
    state.setField(-2, "sight");
  }
}

/// id is actually Level.ID, but it's stored as userdata in lua
const LevelHandle = struct {id: ?*anyopaque};

/// self.camera:centerOn(entity) => pos
/// Returns true camera position after centering
pub const luaCameraCenterOn = toApiFunction(
  "camera:centerOn",
  luaCameraCenterOnInner,
  .{}
) catch unreachable;

pub fn luaCameraCenterOnInner(
  level: LevelHandle,
  entity: struct {id: ECS.Entity.Unmanaged}) !Level.Coord
{
  const pos = mainspace.ecs.get(entity.id, "pos", Level.Coord) orelse
    return error.MissingComponent;

  return luaCameraCenterInner(level, pos);
}

/// self:cameraCenter(pos) => pos
/// Returns true camera position after centering
pub const luaCameraCenter = toApiFunction(
  "cameraCenter",
  luaCameraCenterInner,
  .{}
) catch unreachable;

fn luaCameraCenterInner(level: LevelHandle, pos: Level.Coord)
  Level.Coord
{
  const truePos = pos - graphics.size()/@as(Level.Coord, @splat(2));
  luaCameraSetPosInner(level, truePos);

  return truePos;
}

/// self:cameraSetPos(pos) => nil
pub const luaCameraSetPos = toApiFunction(
  "cameraSetPos",
  luaCameraSetPosInner,
  .{}
) catch unreachable;

fn luaCameraSetPosInner(level: LevelHandle, pos: Level.Coord) void
{
  Level.levels.items[@intFromPtr(level.id)].camPos = pos;
}

fn getLuaLevelPosArgs(self: *lua.Lua)
  struct {levelID: Level.ID, pos: Level.Coord}
{
  if (self.getTop() < 2) self.raiseErrorStr(
    "level:function(pos) expected 2 arguments, got {}", .{self.getTop()}
  );

  self.argExpected(self.isTable(1), 1, "namespace");
  self.argCheck(
    self.getField(1, "parent") == .table, 1, "must have parent member"
  );
  self.argCheck(
    self.getField(-1, "handle") == .light_userdata, 1, "must have handle member"
  );
  // I'm just digging myself deeper into this putrid cesspool
  const levelID: Level.ID =
    if (self.toUserdata(anyopaque, -1)) |id| @intCast(@intFromPtr(id))
    else |_| 0;

  self.argExpected(self.isTable(2), 2, "pos");
  self.argCheck(
    self.getIndex(2, 1) == .number, 1, "must be a number"
  );
  self.argCheck(
    self.getIndex(2, 2) == .number, 1, "must be a number"
  );

  const pos = Level.Coord{
    @intCast(self.toInteger(-2) catch unreachable),
    @intCast(self.toInteger(-1) catch unreachable)
  };

  return .{.levelID = levelID, .pos = pos};
}

const ToApiFuncOptions = struct
{

};
fn toApiFunction(
  comptime name: [:0]const u8,
  comptime function: anytype,
  options: ToApiFuncOptions) error{NotAFunction}!lua.CFn
{
  _ = options;
  if (@typeInfo(@TypeOf(function)) != .@"fn")
  {
    return error.NotAFunction;
  }

  const fnSig = @typeInfo(@TypeOf(function)).@"fn";

  return lua.wrap(struct {fn apiFn(self: *lua.Lua) i32
  {
    if (self.getTop() < fnSig.params.len)
    {
      self.raiseErrorStr(
        "%s expected %I arguments, got %I",
        .{name.ptr, fnSig.params.len, self.getTop()}
      );
    }

    const Args = comptime blk: {
      // We take these by reference in the @Struct() directive, but then leave this stack frame. I think it should be okay because we only need the struct type
      //var argNames: [fnSig.params.len][]const u8 = undefined;
      var argTypes: [fnSig.params.len]type = undefined;
      for (0.., &argTypes, fnSig.params) |i, *arg, param|
      {_ = i;
        //argNames[i] = "Arg" ++ std.fmt.digits2(i);
        arg.* = param.type orelse void;
      }
      break:blk @Tuple(&argTypes);
      //break:blk @Struct(.auto, null, &argNames, &argTypes, &@splat(.{}));
    };
    var args: Args =
      undefined;

    inline for (1.., &args) |i, *arg|
    {
      // Give special access to lua environment
      if (@TypeOf(arg.*) == *lua.Lua)
      {
        arg.* = self;
        continue;
      }

      arg.* = self.toAny(@TypeOf(arg.*), i) catch |e|
      {
        self.raiseErrorStr(
          "%s arg %I expected type %s: %s",
          .{name.ptr, i, @typeName(@TypeOf(arg.*)), @errorName(e).ptr}
        );
      };
    }

    if (fnSig.return_type) |ret|
    {
      const result =
        if (@typeInfo(ret) == .error_union)
          @call(.auto, function, args) catch |e| self.raiseErrorStr(
            "%s failed with error.%s",
            .{name.ptr, @errorName(e).ptr}
          )
        else
          @call(.auto, function, args);

      self.pushAny(result) catch |e| self.raiseErrorStr(
        "%s return failed with result type %s: %s",
        .{name.ptr, @typeName(@TypeOf(result)), @errorName(e).ptr}
      );

      return 1;
    } else
    {
      @call(.auto, function, args);

      return 0;
    }
  }}.apiFn);
}

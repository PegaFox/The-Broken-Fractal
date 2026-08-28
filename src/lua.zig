const Self = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const File = Io.File;
const log = std.log;

const ECS = @import("ecs");
const input = @import("input.zig");
const graphics = @import("graphics.zig");
const Turn = @import("turn.zig");
const Mod = @import("mod.zig");
const Overtime = @import("overtime.zig");
const Sight = @import("sight.zig");
const TileMemory = @import("tile_memory.zig");
const Inventory = @import("inventory.zig");
const Object = @import("object.zig");
const Level = @import("scenes/level.zig");
const Tile = @import("tile.zig");
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

  state.createTable(0, 1);
  // 32 is an approximation
  state.createTable(32, 0);
  state.setField(-2, "actions");
  state.setField(lua.registry_index, "fractal");

  state.createTable(0, 1);
  // 8 is an approximation and it may be smart to check enabled mod count and use that instead
  state.createTable(0, 8);
  state.setField(-2, "mods");

  //state.pushFunction(luaInput);
  //state.setField(-2, "input");

  state.createTable(1, 0);

  state.pushFunction(lua.wrap(luaTiming.start));
  state.setField(-2, "start");
  state.setField(-2, "timing");
  state.setGlobal("fractal");

  return state;
}

pub fn runFile(self: *lua.Lua, io: Io, file: File, name: [:0]const u8)
  error{LuaSyntax, OutOfMemory, LuaRuntime, LuaMsgHandler, LuaGCMetaMethod}!void
{
  try loadFile(self, io, file, name);

  try runFunction(self, .{});
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
pub fn runFunction(self: *lua.Lua, args: lua.Lua.ProtectedCallArgs)
  error{LuaSyntax, OutOfMemory, LuaRuntime, LuaMsgHandler, LuaGCMetaMethod}!void
{
  self.protectedCall(args) catch |e|
  {
    // Types are commented out if I can't think of a good way to log them
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

var printedTables = std.AutoHashMapUnmanaged().empty;
var luaPrintEndsInNewline = true;
pub fn luaPrint(self: *lua.Lua) i32
{
  const argNum: u31 = @intCast(self.getTop());
  // Reset the stack in case we're calling this from zig
  defer self.setTop(argNum);

  //self.checkStackErr(1, null);

  for (1..argNum+1) |arg|
  {
    //self.setTop(argNum);
    switch (self.typeOf(@intCast(arg)))
    {
      .table => {
        const revertNewline = luaPrintEndsInNewline;
        luaPrintEndsInNewline = false;
        defer if (revertNewline) {luaPrintEndsInNewline = true;};

        std.debug.assert(
          self.getGlobal("print") catch unreachable == .function);
        const printIdx = self.getTop();

        log.info("{{ ", .{});
        self.pushNil();

        var first = true;
        while (self.next(@intCast(arg)))
        {
          // We don't want to add a comma the first time
          if (!first)
          {
            log.info(", ", .{});
          }
          first = false;

          self.pushValue(printIdx);
          self.pushValue(-3);
          self.protectedCall(.{.args = 1}) catch self.raiseError();
          log.info(" = ", .{});
          self.pushValue(printIdx);
          self.rotate(-2, 1);
          self.protectedCall(.{.args = 1}) catch self.raiseError();
        }
        log.info(" }}", .{});
      },
      else => {
        const string = self.toStringEx(@intCast(arg));
        log.info("{s}", .{string});
        self.pop(1);
      }
    }
  }

  if (luaPrintEndsInNewline)
  {
    log.info("\n", .{});
  }
  
  return 0;
}

var currentInput: []const u8 = "";
/// input() => "current input"
/// Polls for and reads the current input, returning it but not popping it
/// input(input) => bool
/// Returns if the current input equals the arg
pub const luaInput = lua.wrap(luaInputInner);

fn luaInputInner(state: *lua.Lua) !i32
{
  if (currentInput.len == 0)
  {
    // The io argument isn't used right now and it would be annoying to find some way to pass the io implementation to the function manually, so I'm leaving it blank for now
    currentInput = try input.getInput(undefined);
  }

  if (state.getTop() > 0)
  {
    const @"test" = try state.toString(1);
    const testIsInput = std.mem.eql(u8, currentInput, @"test");

    state.pushBoolean(testIsInput);

    if (testIsInput)
    {
      currentInput = "";
    }
  } else
  {
    _ = state.pushString(currentInput);
  }

  return 1;
}

pub const luaTiming = struct
{
  startTime: i64,

  pub fn start(state: *lua.Lua) i32
  {
    state.createTable(2, 0);

    const nanoseconds =
      std.Io.Timestamp.now(mainspace.io, .awake).toNanoseconds();
    state.pushInteger(@truncate(nanoseconds));
    state.setField(-2, "startTime");

    state.pushFunction(toApiFunction("timing:stop", stop, .{}));
    state.setField(-2, "stop");

    return 1;
  }

  pub fn stop(self: @This()) f64
  {
    const startTime = std.Io.Timestamp.fromNanoseconds(self.startTime);
    const durationNs: f64 =
      @floatFromInt(startTime.untilNow(mainspace.io, .awake).toNanoseconds());

    return durationNs / std.time.ns_per_s;
  }
};

pub const luaTile = struct
{
  parent: LevelHandle,

  /// self.tiles:get(pos) => {"mod", "name"}
  pub const get = toApiFunction("tiles:get", getInner, .{});

  fn getInner(
    self: luaTile,
    pos: Level.Coord) ![2][]const u8
  {
    const tile = try Level.levels.items[self.parent.handle].getTile(pos);
  
    return .{
      Mod.findTileMod(tile.type).name,
      tile.getStaticData().?.name
    };
  }
  
  /// self.tiles:getInfo(pos) => {
  ///   name = "cyanideCarpet",
  ///   walkable = true,
  ///   color = {"r": 1.0, "g": 1.0, "b": 1.0},
  ///   wallConnect = false,
  ///   ch = "."
  /// }
  /// This is slightly faster than calling luaTileGet then accessing it using the global table
  pub const getInfo = toApiFunction("tiles:getInfo", getInfoInner, .{});

  fn getInfoInner(
    self: luaTile,
    pos: Level.Coord)
    !struct {
      name: []const u8,
      walkable: bool,
      color: struct {r: f32, g: f32, b: f32},
      wallConnect: bool,
      ch: []const u8,
    }
  {
    const tile = try Level.levels.items[self.parent.handle].getTile(pos);
    const data = tile.getStaticData().?;
  
    return .{
      .name = data.name,
      .walkable = data.walkable,
      .color = .{
        .r = data.color[0],
        .g = data.color[1],
        .b = data.color[2]
      },
      .wallConnect = data.wallConnect,
      .ch = (&data.ch)[0..1],
    };
  }
  
  /// self.tiles:iterate() => iterator
  /// Used with for loops to iterate over a level's tiles
  /// The key returned by the iterator is invalidated each loop. keys must be deep copied for long storage
  pub const iterate = lua.wrap(iterateInner);
  
  fn iterateInner(state: *lua.Lua) i32
  {
    state.argCheck(state.getField(1, "parent") == .table, 1, "Not a namespace");
    state.argCheck(
      state.getField(-1, "handle") == .number,
      1,
      "Not a level"
    );
  
    state.pushValue(-1);
    // Store current index as closure
    state.pushInteger(0);
    // Reuse key table for performance
    state.createTable(2, 0);
    state.pushClosure(lua.wrap(
      struct {fn nextTile(self: *lua.Lua) c_int
        //error{NotANamespace, NotALevel}!
        //?struct {Level.Coord, ECS.Entity.Unmanaged}
      {
        const levelId: Level.ID =
          @intCast(self.toInteger(lua.Lua.upvalueIndex(1)) catch unreachable);
  
        const index = self.toInteger(lua.Lua.upvalueIndex(2)) catch unreachable;
        self.pushInteger(index + 1);
        self.replace(lua.Lua.upvalueIndex(2));
  
        const tiles = &Level.levels.items[levelId].tiles;
  
        if (index < tiles.count())
        {
          const kv = tiles.entries.get(@intCast(index));

          // The catch unreachable here may be incorrect if the key type is changed, so we assert the type here
          std.debug.assert(
            @TypeOf(kv.key) == Level.Coord
          );

          self.pushValue(lua.Lua.upvalueIndex(3));
          self.pushInteger(kv.key[0]);
          self.setIndex(-2, 1);
          self.pushInteger(kv.key[1]);
          self.setIndex(-2, 2);
          //self.pushAny(tiles.keys()[@intCast(index)]) catch unreachable;
          self.pushInteger(kv.value.id);
          return 2;
        } else 
        {
          return 0;
        }
      }}.nextTile), 3);
  
    return 1;
  }
  
  /// self.tiles:remove(pos) => bool
  /// Removes tile at pos
  /// Returns whether there was a tile there
  pub const remove = toApiFunction("tiles:remove", removeInner, .{});
  
  fn removeInner(self: luaTile, pos: Level.Coord) bool
  {
    return Level.levels.items[self.parent.handle].tiles.swapRemove(pos);
  }
  
  /// self.tiles:count() => int
  /// Returns size of level's tilemap
  pub const count = toApiFunction("tiles:count", countInner, .{});
  
  fn countInner(self: luaTile) u32
  {
    //log.debug("{} tiles in {s}\n", .{Level.levels.items[@intFromPtr(level.handle)].tiles.count(), Level.levels.items[@intFromPtr(level.handle)].name});
    return
      @intCast(Level.levels.items[self.parent.handle].tiles.count());
  }
};

pub const luaObject = struct
{
  /// self.objects:get(index) or
  /// self.objects:get(pos) or
  /// self.objects.get(index) => {
  ///   id: ECS.Entity.Unmanaged,
  ///   if hasComponent(sight) sight
  /// }
  pub fn get(state: ?*lua.LuaState) callconv(.c) c_int
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
  
      generateLua(
        self,
        &mainspace.ecs,
        Level.objects.items[@intCast(index)]
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
  
        generateLua(
          self,
          &mainspace.ecs,
          Level.objects.items[@intCast(index)]
        );
  
        return 1;
      } else
      {
        // TODO: This
      }
    }
  
    return 0;
  }

  /// self.objects:add(type, object) or
  /// self.objects.add(type, object) => {
  ///   id: ECS.Entity.Unmanaged,
  ///   if hasComponent(sight) sight
  /// }
  pub fn add(state: *lua.Lua) !i32
  {
    // Remove self argument if present
    if (state.getTop() > 2)
    {
      state.remove(1);
    }

    state.rotate(1, 1);
    std.debug.assert(state.getIndex(-1, 1) == .string);
    std.debug.assert(state.getIndex(-2, 2) == .string);

    const objectType = Object.nameTypes.get(.{
      .mod = state.toString(-2) catch unreachable,
      .name = state.toString(-1) catch unreachable
    }) orelse return error.InvalidIdentifier;
    // The type identifier can leave the scope now
    state.pop(3);

    if (objectType >= Object.staticData.items.len)
      return error.InvalidIdentifier;

    state.pushInteger(objectType);

    state.setField(1, "type");

    const object = generateZig(state, state.allocator(), &mainspace.ecs) catch
    {
      state.argError(1, "ExpectedArgument");
      return 0;
    };

    try Level.objects.append(state.allocator(), object);

    return 0;
  }

  /// Pushes an object table with the object's components onto the lua stack
  /// Does not verify stack space
  pub fn generateLua(state: *lua.Lua, ecs: *ECS, object: Object) void
  {
    state.createTable(0, 5);

    const objectTableIdx = state.getTop();

    state.pushInteger(object.type);
    state.setField(objectTableIdx, "type");

    state.pushInteger(object.id);
    state.setField(objectTableIdx, "id");
  
    std.debug.assert(
      state.getGlobal("fractal") catch unreachable == .table
    );
    std.debug.assert(state.getField(-1, "mods") == .table);
    _ = state.pushString(Mod.findObjectMod(object.type).name);
    std.debug.assert(state.getTable(-2) == .table);

    state.setField(objectTableIdx, "mod");

    var it = ecs.componentTable.iterator();
    while (it.next()) |arr|
    {
      switch (std.hash_map.hashString(arr.value_ptr.typeID))
      {
        std.hash_map.hashString(@typeName(Object.Pos)) =>
        {
          if (ecs.get(object.id, arr.key_ptr.*, Object.Pos) == null)
          {
            break;
          }

          state.createTable(0, 3);
          state.pushValue(objectTableIdx);
          state.setField(-2, "parent");
          state.pushFunction(toApiFunction(
            "object.pos:get",
            struct {fn get(
              self: struct {parent: struct {id: ECS.Entity.Unmanaged}})
                Level.Coord
              {
                return mainspace.ecs.get(
                  self.parent.id, "pos", Object.Pos
                ).?.pos;
              }}.get,
            .{}
          ));
          state.setField(-2, "get");
          state.pushFunction(toApiFunction(
            "object.pos:set",
            struct {fn set(
              self: struct {parent: struct {id: ECS.Entity.Unmanaged}},
              newPos: Level.Coord) void
              {
                const pos =
                  mainspace.ecs.getPtr(self.parent.id, "pos", Object.Pos).?;

                //Level.levels.items[Level.currentLevel].getTile();

                pos.pos = newPos;
              }}.set,
            .{}
          ));
          state.setField(-2, "set");
          state.setField(objectTableIdx, "pos");
        },
        std.hash_map.hashString(@typeName(Sight)) =>
        {
          if (ecs.get(object.id, arr.key_ptr.*, Sight) == null)
          {
            break;
          }

          state.createTable(0, 1);
  
          state.pushValue(objectTableIdx);
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
          ), 1);
          state.setField(-2, "inView");

          state.pushValue(objectTableIdx);
          state.pushClosure(toApiFunction(
            "object.sight.draw",
            struct {fn draw(self: *lua.Lua) !void
            {
              std.debug.assert(
                self.getField(lua.Lua.upvalueIndex(1), "id") == .number
              );

              const objectId: ECS.Entity.Managed = .{
                .parent = &mainspace.ecs,
                .id = @intCast(try self.toInteger(-1)),
              };
  
              if (objectId.get("sight", Sight) == null)
              {
                return error.InvalidComponent;
              }

              try Level.sightToDraw.append(Level.gpa, objectId.id);
  
              return;
            }}.draw, .{}
          ), 1);
          state.setField(-2, "draw");

          state.setField(objectTableIdx, "sight");
        },
        std.hash_map.hashString(@typeName(TileMemory)) =>
        {
          if (ecs.get(object.id, arr.key_ptr.*, TileMemory) == null)
          {
            break;
          }

          state.createTable(0, 1);
  
          state.pushValue(objectTableIdx);
          state.pushClosure(toApiFunction(
            "object.memory.draw",
            struct {fn draw(self: *lua.Lua) !void
            {
              std.debug.assert(
                self.getField(lua.Lua.upvalueIndex(1), "id") == .number
              );

              const objectId: ECS.Entity.Managed = .{
                .parent = &mainspace.ecs,
                .id = @intCast(try self.toInteger(-1)),
              };
  
              if (objectId.get("tileMemory", TileMemory) == null)
              {
                return error.InvalidComponent;
              }

              try Level.memoryToDraw.append(Level.gpa, objectId.id);
  
              return;
            }}.draw, .{}
          ), 1);
          state.setField(-2, "draw");

          state.setField(objectTableIdx, "memory");
        },
        std.hash_map.hashString(@typeName(Overtime)) =>
        {
          if (ecs.get(object.id, arr.key_ptr.*, Overtime) == null)
          {
            break;
          }

          _ = state.pushString(arr.key_ptr.*);
          const componentNameIdx = state.getTop();

          state.createTable(2, 0);

          state.createTable(2, 0);

          state.pushInteger(object.id);
          state.pushValue(componentNameIdx);
          state.pushClosure(toApiFunction(
            "overtime.value.get",
            struct {fn get(self: *lua.Lua) u32 {
              const objectId: ECS.Entity.Unmanaged = @intCast(
                self.toInteger(lua.Lua.upvalueIndex(1)) catch unreachable);
              const componentName =
                self.toString(lua.Lua.upvalueIndex(2)) catch unreachable;

              const component =
                mainspace.ecs.getPtr(objectId, componentName, Overtime).?;
              
              return component.valuePtr().*;
          }}.get,
          .{}), 2);
          state.setField(-2, "get");

          state.pushInteger(object.id);
          state.pushValue(componentNameIdx);
          state.pushClosure(toApiFunction(
            "overtime.value.set",
            struct {fn set(self: *lua.Lua, value: u32) void {
              const objectId: ECS.Entity.Unmanaged = @intCast(
                self.toInteger(lua.Lua.upvalueIndex(1)) catch unreachable);
              const componentName =
                self.toString(lua.Lua.upvalueIndex(2)) catch unreachable;

              const component =
                mainspace.ecs.getPtr(objectId, componentName, Overtime).?;
              
              component.valuePtr().* = value;
          }}.set,
          .{}), 2);
          state.setField(-2, "set");

          state.setField(-2, "value");

          state.createTable(2, 0);

          state.pushInteger(object.id);
          state.pushValue(componentNameIdx);
          state.pushClosure(toApiFunction(
            "overtime.value.get",
            struct {fn get(self: *lua.Lua) u32 {
              const objectId: ECS.Entity.Unmanaged = @intCast(
                self.toInteger(lua.Lua.upvalueIndex(1)) catch unreachable);
              const componentName =
                self.toString(lua.Lua.upvalueIndex(2)) catch unreachable;

              const component =
                mainspace.ecs.getPtr(objectId, componentName, Overtime).?;
              
              return component.valuePtr().*;
          }}.get,
          .{}), 2);
          state.setField(-2, "get");

          state.pushInteger(object.id);
          state.pushValue(componentNameIdx);
          state.pushClosure(toApiFunction(
            "overtime.value.set",
            struct {fn set(self: *lua.Lua, value: u32) void {
              const objectId: ECS.Entity.Unmanaged = @intCast(
                self.toInteger(lua.Lua.upvalueIndex(1)) catch unreachable);
              const componentName =
                self.toString(lua.Lua.upvalueIndex(2)) catch unreachable;

              const component =
                mainspace.ecs.getPtr(objectId, componentName, Overtime).?;
              
              component.valuePtr().* = value;
          }}.set,
          .{}), 2);
          state.setField(-2, "set");

          state.setField(-2, "change");

          state.setTable(objectTableIdx);
        },
        std.hash_map.hashString(@typeName(Inventory)) =>
        {
          if (ecs.get(object.id, arr.key_ptr.*, Inventory) == null)
          {
            break;
          }

          _ = state.pushString(arr.key_ptr.*);
          const componentNameIdx = state.getTop();

          const InventoryUserdata = struct {
            // The object that owns the inventory
            object: Object
          };
          state.newUserdata(InventoryUserdata, 0).* = .{.object = object};

          state.createTable(0, 2);
          _ = state.pushValue(componentNameIdx);
          state.pushClosure(toApiFunction("object.inventory.__index",
            struct {fn inventoryIndex(luaState: *lua.Lua) u32
            {
              const inventoryReference =
                luaState.toUserdata(InventoryUserdata, 1) catch |e|
                  luaState.raiseErrorStr(
                    "object.inventory.__index arg 1 expected type userdata: %s",
                    .{@errorName(e).ptr}
                  );
              const index: usize = @intCast(luaState.toInteger(2) catch |e|
                luaState.raiseErrorStr(
                  "object.inventory.__index arg 2 expected type usize: %s",
                  .{@errorName(e).ptr}
                ));

              const inventory = mainspace.ecs.getPtr(
                inventoryReference.object.id,
                luaState.toString(lua.Lua.upvalueIndex(1)) catch unreachable,
                Inventory
              ).?;

              generateLua(
                luaState,
                &mainspace.ecs,
                inventory.items.items[index]
              );
              return 1;
            }}.inventoryIndex,
          .{.resultOnStack = true}), 1);
          state.setField(-2, "__index");
          _ = state.pushValue(componentNameIdx);
          state.pushClosure(lua.wrap(
            struct {fn inventoryNewIndex(luaState: *lua.Lua) u32
            {
              const inventoryReference =
                luaState.toUserdata(InventoryUserdata, 1) catch |e|
                  luaState.raiseErrorStr(
                    "object.inventory.__newindex arg 1 expected type userdata: %s",
                    .{@errorName(e).ptr}
                  );
              const index: usize = @intCast(luaState.toInteger(2) catch |e|
                luaState.raiseErrorStr(
                  "object.inventory.__newindex arg 2 expected type usize: %s",
                  .{@errorName(e).ptr}
                ));

              const inventory = mainspace.ecs.getPtr(
                inventoryReference.object.id,
                luaState.toString(lua.Lua.upvalueIndex(1)) catch unreachable,
                Inventory
              ).?;

              if (index < inventory.items.items.len)
              {
                luaState.raiseErrorStr(
                  "Base reassigning an object is not allowed (yet)", .{}
                );
              } else
              {
                inventory.items.append(luaState.allocator(),
                  generateZig(
                    luaState,
                    luaState.allocator(),
                    &mainspace.ecs,
                  ) catch |e|
                    luaState.raiseErrorStr(
                      "Failed to create new object: %s",
                      .{@errorName(e).ptr}
                    )
                ) catch |e|
                  luaState.raiseErrorStr(
                    "Failed to add object to inventory: %s",
                    .{@errorName(e).ptr}
                  );
              }
              return 1;
            }}.inventoryNewIndex
          ), 1);
          state.setField(-2, "__newindex");
          state.setMetatable(-2);

          state.setTable(objectTableIdx);
        },
        else => log.warn(
          "unknown component \"{s}\", consider adding a translation case\n",
          .{arr.key_ptr.*}
        ),
      }
    }

    state.setTop(objectTableIdx);
  }

  /// The inverse of generateLua, converting the lua table at the top of the stack into a new object and popping the top
  pub fn generateZig(state: *lua.Lua, allocator: Allocator, ecs: *ECS)
    error{OutOfMemory, ExpectedArgument, ExpectedTable}!Object
  {
    const top = state.getTop();

    if (top == 0)
    {
      return error.ExpectedArgument;
    }

    var result = Object{.type = 0, .id = ecs.addEntity(.{}).id};

    if (state.getField(top, "type") == .number and state.isInteger(-1))
    {
      // Assume type field fits inside of Object.Type since this function will likely be called from LuaObject.add
      result.type = @intCast(state.toInteger(-1) catch unreachable);
    }
    state.setTop(top);

    try Turn.push(allocator, ecs, result);

    if (
      state.getField(top, "pos") == .table and
      state.getIndex(top+1, 1) == .number and
      state.isInteger(-1) and
      state.getIndex(top+1, 2) == .number and 
      state.isInteger(-1))
    {
      log.debug("pos = {}\n", .{.{state.toInteger(-2), state.toInteger(-1)}});
      ecs.addC(
        result.id,
        "pos",
        Object.Pos{
          .pos = .{
            @truncate(state.toInteger(-2) catch unreachable),
            @truncate(state.toInteger(-1) catch unreachable)
          },
          .next = undefined
        }
      );
    }
    state.setTop(top);

    if (
      state.getField(top, "sight") == .table and
      state.getField(-1, "radius") == .number and
      state.isInteger(-1))
    {
      ecs.addC(
        result.id,
        "sight",
        Sight{
          .radius = @truncate(@max(0, state.toInteger(-1) catch unreachable)),
          .view = .empty,
        }
      );
    }
    state.setTop(top);

    if (state.getField(top, "memory") == .table)
    {
      ecs.addC(
        result.id,
        "tileMemory",
        TileMemory{
          .tiles = .empty,
        }
      );
    }
    state.setTop(top);

    if (state.getField(top, "inventory") == .table)
    {
      ecs.addC(result.id, "inventory", Inventory{
        .capacity =
          if (state.getField(2, "capacity") == .number)
            @floatCast(state.toNumber(-1) catch unreachable)
          else 0,
        .items = 
          if (state.getField(2, "items") == .table)
          arr:{
            state.len(-1);
            const itemCount: usize =
              @intCast(state.toInteger(-1) catch unreachable);
            state.pop(1);

            const itemArr = try allocator.alloc(Object, itemCount);
            for (0..itemCount) |i|
            {
              if (state.getIndex(-1, @intCast(i+1)) != .table)
              {
                return error.ExpectedTable;
              }

              itemArr[i] = try generateZig(state, allocator, ecs);
            }

            break:arr .fromOwnedSlice(itemArr);
          }
          else .empty,
      });
    }
    state.setTop(top);

    inline for ([_][:0]const u8{"energy", "food", "fluid", "sanity"}) |stat|
    {
      if (
        state.getField(top, stat) == .table and
        state.getField(top+1, "value") == .number and 
        state.isInteger(-1))
      {
        _ = state.getField(top+1, "rate");

        ecs.addC(
          result.id,
          stat,
          Overtime{
            .value = .{
              .value =
                @truncate(@max(0, state.toInteger(-2) catch unreachable))
            },
            .delta = @truncate(state.toInteger(-1) catch -1),
          }
        );
      }
      state.setTop(top);
    }

    // Remove argument from the stack
    state.pop(1);
    return result;
  }
};

const LevelHandle = struct {handle: Level.ID};

pub const luaCamera = struct
{
  parent: LevelHandle,

  /// self.camera:centerOn(entity) => pos
  /// Returns true camera position after centering
  pub const centerOn = toApiFunction("camera:centerOn", centerOnInner, .{});
  
  pub fn centerOnInner(
    self: @This(),
    entity: struct {id: ECS.Entity.Unmanaged}) !Level.Coord
  {
    const pos = mainspace.ecs.get(entity.id, "pos", Object.Pos) orelse
      return error.MissingComponent;
  
    return centerInner(self, pos.pos);
  }
  
  /// self.camera:center(pos) => pos
  /// Returns true camera position after centering
  pub const center = toApiFunction("camera:center", centerInner, .{});
  
  fn centerInner(self: @This(), pos: Level.Coord)
    Level.Coord
  {
    const truePos = pos - graphics.size()/@as(Level.Coord, @splat(2));

    setPosInner(self, truePos);
  
    return truePos;
  }
  
  /// self:camera:setPos(pos) => nil
  pub const setPos = toApiFunction("camera:setPos", setPosInner, .{});
  
  fn setPosInner(
    self: @This(),
    pos: Level.Coord) void
  {
    Level.levels.items[self.parent.handle].camPos = pos;
  }
};

const ToApiFuncOptions = struct
{
  /// Allows for lua style function returns, where the function returns the result count on the stack
  resultOnStack: bool = false,
};
pub fn toApiFunction(
  comptime name: [:0]const u8,
  comptime function: anytype,
  comptime options: ToApiFuncOptions) lua.CFn
{
  if (@typeInfo(@TypeOf(function)) != .@"fn")
  {
    @compileError(
      "toApiFunction expected function, got " ++ @typeName(@TypeOf(function))
    );
  }

  const fnSig = @typeInfo(@TypeOf(function)).@"fn";

  return lua.wrap(struct {fn apiFn(self: *lua.Lua) i32
  {
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

    var trueArgCount: u32 = 0;
    inline for (1.., &args) |i, *arg|
    {
      // Give special access to lua environment
      if (@TypeOf(arg.*) == *lua.Lua)
      {
        arg.* = self;
        continue;
      }
      trueArgCount += 1;

      arg.* = self.toAny(@TypeOf(arg.*), i) catch |e|
      blk:{
        // toAny gives an error with optional void pointers, so here
        if (e != error.ExpectedUserdata)
        {
          self.raiseErrorStr(
            "%s arg %I expected type %s: %s",
            .{name.ptr, i, @typeName(@TypeOf(arg.*)), @errorName(e).ptr}
          );
        } else
        {
          break:blk std.mem.zeroes(@TypeOf(arg.*));
        }
      };
    }

    if (self.getTop() < trueArgCount)
    {
      self.raiseErrorStr(
        "%s expected %I arguments, got %I",
        .{name.ptr, fnSig.params.len, self.getTop()}
      );
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

      if (!options.resultOnStack)
      {
        self.pushAny(result) catch |e| self.raiseErrorStr(
          "%s return failed with result type %s: %s",
          .{name.ptr, @typeName(@TypeOf(result)), @errorName(e).ptr}
        );
      }

      return 1;
    } else
    {
      @call(.auto, function, args);

      return 0;
    }
  }}.apiFn);
}

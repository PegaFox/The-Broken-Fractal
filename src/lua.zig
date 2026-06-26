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
const Object = @import("object.zig");
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

  state.createTable(0, 1);
  // 32 is an approximation
  state.createTable(32, 0);
  state.setField(-2, "actions");
  state.setField(lua.registry_index, "fractal");

  state.createTable(0, 1);
  // 8 is an approximation and it may be smart to check enabled mod count and use that instead
  state.createTable(0, 8);
  state.setField(-2, "mods");

  state.pushFunction(luaInput);
  state.setField(-2, "input");

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
fn luaPrint(self: *lua.Lua) i32
{
  const argNum = @max(0, self.getTop());

  self.checkStackErr(1, null);

  for (1..argNum+1) |arg|
  {
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

pub const luaTile = struct
{
  /// self.tiles:get(pos) => {"mod", "name"}
  pub fn get(state: ?*lua.LuaState) callconv(.c) c_int
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
  
  /// self.tiles:getInfo(pos) => {
  ///   name = "cyanideCarpet",
  ///   walkable = true,
  ///   color = {"r": 1.0, "g": 1.0, "b": 1.0},
  ///   wallConnect = false,
  ///   ch = "."
  /// } or nil
  /// This is slightly faster than calling luaTileGet then accessing it using the global table
  pub fn getInfo(state: ?*lua.LuaState) callconv(.c) c_int
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
  
  /// self.tiles:iterate() => iterator
  /// Used with for loops to iterate over a level's tiles
  pub const iterate = lua.wrap(iterateInner);
  
  fn iterateInner(state: *lua.Lua) i32
  {
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
          std.debug.assert(
            @TypeOf(tiles.keys()[@intCast(index)]) == Level.Coord
          );

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
  
  /// self.tiles:remove(pos) => bool
  /// Removes tile at pos
  /// Returns whether there was a tile there
  pub const remove = toApiFunction(
    "tiles:remove",
    removeInner,
    .{}
  ) catch unreachable;
  
  fn removeInner(level: LevelHandle, pos: Level.Coord) bool
  {
    return Level.levels.items[@intFromPtr(level.handle)].tiles.swapRemove(pos);
  }
  
  /// self.tiles:count() => int
  /// Returns size of level's tilemap
  pub const count = toApiFunction(
    "tiles:count",
    countInner,
    .{}
  ) catch unreachable;
  
  fn countInner(level: LevelHandle) u32
  {
    return
      @intCast(Level.levels.items[@intFromPtr(level.handle)].tiles.count());
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

    state.pushInteger(object.id);
    state.setField(objectTableIdx, "id");
  
    if (ecs.get(object.id, "objectType", Object.Type)) |@"type"|
    {
      state.pushInteger(@"type");
      state.setField(objectTableIdx, "type");

      std.debug.assert(state.getGlobal("fractal") catch unreachable == .table);
      std.debug.assert(state.getField(-1, "mods") == .table);
      _ = state.pushString(Mod.findObjectMod(@"type").name);
      std.debug.assert(state.getTable(-2) == .table);

      state.setField(objectTableIdx, "mod");
    }

    if (ecs.get(object.id, "pos", Level.Coord)) |_|
    {
      state.createTable(0, 3);
      state.pushValue(objectTableIdx);
      state.setField(-2, "parent");
      state.pushFunction(toApiFunction(
        "object.pos:get",
        struct {fn get(
          self: struct {parent: struct {id: ECS.Entity.Unmanaged}}) Level.Coord
          {
            return mainspace.ecs.get(self.parent.id, "pos", Level.Coord).?;
          }}.get,
        .{}
      ) catch unreachable);
      state.setField(-2, "get");
      state.pushFunction(toApiFunction(
        "object.pos:set",
        struct {fn set(
          self: struct {parent: struct {id: ECS.Entity.Unmanaged}},
          newPos: Level.Coord) void
          {
            mainspace.ecs.getPtr(self.parent.id, "pos", Level.Coord).?.* =
              newPos;
          }}.set,
        .{}
      ) catch unreachable);
      state.setField(-2, "set");
      state.setField(objectTableIdx, "pos");
    }

    if (ecs.get(object.id, "sight", Sight)) |_|
    {
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
      ) catch unreachable, 1);
      
      state.setField(-2, "inView");
      state.setField(objectTableIdx, "sight");
    }

    state.setTop(objectTableIdx);
  }

  /// The inverse of generateLua, converting a lua table into a new object
  pub fn generateZig(state: *lua.Lua, allocator: Allocator, ecs: *ECS)
    error{OutOfMemory, ExpectedArgument}!Object
  {
    if (state.getTop() == 0)
    {
      return error.ExpectedArgument;
    }

    const result = Object{.id = ecs.addEntity(.{}).id};
    try Turn.push(allocator, ecs, result);

    if (state.getField(1, "type") == .number and state.isInteger(-1))
    {
      // Assume type field fits inside of Object.Type since this function will likely be called from LuaObject.add
      ecs.addC(
        result.id,
        "objectType",
        @as(Object.Type, @intCast(state.toInteger(-1) catch unreachable))
      );
    }
    state.setTop(1);

    _ = state.getField(1, "pos");
    _ = state.getIndex(-1, 1);
    _ = state.getIndex(-2, 2);
    log.debug("pos = {}\n", .{.{state.toInteger(-2), state.toInteger(-1)}});
    if (
      state.getField(1, "pos") == .table and
      state.getIndex(-1, 1) == .number and
      state.isInteger(-1) and
      state.getIndex(-2, 2) == .number and 
      state.isInteger(-1))
    {
      ecs.addC(
        result.id,
        "pos",
        Level.Coord{
          @truncate(state.toInteger(-2) catch unreachable),
          @truncate(state.toInteger(-1) catch unreachable)
        }
      );
    }
    state.setTop(1);

    if (
      state.getField(1, "sight") == .table and
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
    state.setTop(1);

    if (state.getField(1, "memory") == .table)
    {
      ecs.addC(
        result.id,
        "tileMemory",
        TileMemory{
          .tiles = .empty,
        }
      );
    }
    state.setTop(1);

    inline for ([_][:0]const u8{"energy", "food", "fluid", "sanity"}) |stat|
    {
      if (
        state.getField(1, stat) == .table and
        state.getField(2, "value") == .number and 
        state.isInteger(-1))
      {
        _ = state.getField(2, "rate");

        ecs.addC(
          result.id,
          stat,
          Overtime{
            .value = .{
              .value =
                @truncate(@max(0, state.toInteger(-2) catch unreachable))
            },
            .moveRate = @truncate(state.toInteger(-1) catch -1),
          }
        );
      }
      state.setTop(1);
    }

    return result;
  }
};

/// id is actually Level.ID, but it's stored as userdata in lua
const LevelHandle = struct {handle: ?*anyopaque};

pub const luaCamera = struct
{
  parent: LevelHandle,

  /// self.camera:centerOn(entity) => pos
  /// Returns true camera position after centering
  pub const centerOn = toApiFunction(
    "camera:centerOn",
    centerOnInner,
    .{}
  ) catch unreachable;
  
  pub fn centerOnInner(
    self: @This(),
    entity: struct {id: ECS.Entity.Unmanaged}) !Level.Coord
  {
    const pos = mainspace.ecs.get(entity.id, "pos", Level.Coord) orelse
      return error.MissingComponent;
  
    return centerInner(self, pos);
  }
  
  /// self.camera:centerOn(pos) => pos
  /// Returns true camera position after centering
  pub const center = toApiFunction(
    "cameraCenter",
    centerInner,
    .{}
  ) catch unreachable;
  
  fn centerInner(self: @This(), pos: Level.Coord)
    Level.Coord
  {
    const truePos = pos - graphics.size()/@as(Level.Coord, @splat(2));
    setPosInner(self, truePos);
  
    return truePos;
  }
  
  /// self:cameraSetPos(pos) => nil
  pub const setPos = toApiFunction(
    "cameraSetPos",
    setPosInner,
    .{}
  ) catch unreachable;
  
  fn setPosInner(
    self: @This(),
    pos: Level.Coord) void
  {
    Level.levels.items[@intFromPtr(self.parent.handle)].camPos = pos;
  }
};

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
    self.getIndex(2, 1) == .number, 1, "must be an integer"
  );
  self.argCheck(
    self.isInteger(-1), 1, "must be an integer"
  );
  self.argCheck(
    self.getIndex(2, 2) == .number, 1, "must be an integer"
  );
  self.argCheck(
    self.isInteger(-1), 1, "must be an integer"
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

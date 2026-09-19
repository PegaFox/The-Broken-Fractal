const Self = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const File = Io.File;
const log = std.log;

const ECS = @import("ecs");
const input = @import("input.zig");
const graphics = @import("graphics.zig");
const ui = @import("ui.zig");
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

  state.createTable(0, 2);
  // Used for storing pending action functions for objects
  // 32 is an approximation
  state.createTable(32, 0);
  state.setField(-2, "actions");
  // Used for storing pending threads waiting for the engine
  // 4 is an approximation
  state.createTable(4, 0);
  state.setField(-2, "threads");
  // Used for storing generic lua tables for entities
  // Currently only used by tiles
  // 64 is an approximation
  state.createTable(64, 0);
  state.setField(-2, "modData");
  state.setField(lua.registry_index, "fractal");

  state.createTable(0, 1);
  // 8 is an approximation and it may be smart to check enabled mod count and use that instead
  state.createTable(0, 8);
  state.setField(-2, "mods");

  state.pushFunction(luaInput);
  state.setField(-2, "input");

  state.pushFunction(luaPrompt);
  state.setField(-2, "prompt");

  state.pushFunction(lua.wrap(openWindow));
  state.setField(-2, "openWindow");

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
pub fn runFunction(
  self: *lua.Lua,
  args: lua.Lua.ProtectedCallArgs)
  error{LuaSyntax, OutOfMemory, LuaRuntime, LuaMsgHandler, LuaGCMetaMethod}!void
{
  self.protectedCall(args) catch |e|
  {
    logLuaError(self);

    self.pop(1);
    return e;
  };
}

pub const PausedThread = struct
{
  pub const WaitCondition = enum {
    /// Wait for input to be available
    Input,
    /// Wait for current window to close
    Window
  };

  thread: *lua.Lua,
  waitCondition: WaitCondition//*const fn (state: *lua.Lua) bool
};

/// Logs an error if the function fails
/// Assumes that any yield from the called function will be compatible with PausedThread
/// If thread is null, takes args from self
/// If return value is null, stores results in self
pub fn runCoroutine(
  self: *lua.Lua,
  thread: ?PausedThread,
  // mfw lua expects i32 for arg counts
  argCount: u31)
  error{LuaSyntax, OutOfMemory, LuaRuntime, LuaMsgHandler, LuaGCMetaMethod}!
  ?PausedThread
{
  if (thread) |t|
  {
    const resumeThread = switch (t.waitCondition)
    {
      .Input => input.currentInput != null,
      .Window => !ui.currentWindow.isOpen(),
    };

    if (!resumeThread)
    {
      return t;
    }
  }

  const state = if (thread) |t| t.thread else self.newThread();

  // Gotta move args to state
  if (thread == null)
  {
    const threadIndex = self.getTop();
    // Store the thread object in the registry using the thread pointer as a key
    std.debug.assert(self.getField(lua.registry_index, "fractal") == .table);
    std.debug.assert(self.getField(-1, "threads") == .table);
    self.pushLightUserdata(state);
    self.rotate(threadIndex, -1);
    self.setTable(-3);
    self.setTop(threadIndex-1);

    // Argcount plus the thread main function
    self.xMove(state, argCount+1);
  }

  //log.debug("main: \n", .{});
  //var i: i32 = self.getTop();
  //while (i > 0): (i -= 1)
  //{
  //  log.debug("{}: ", .{i});
  //  printValue(self, i, 2);
  //  log.debug("\n", .{});
  //}

  //log.debug("thread: \n", .{});
  //i = state.getTop();
  //while (i > 0): (i -= 1)
  //{
  //  log.debug("{}: ", .{i});
  //  printValue(state, i, 2);
  //  log.debug("\n", .{});
  //}

  log.debug("Running thread with state \"{}\"\n", .{state.status()});
  var results: i32 = undefined;
  const code = state.resumeThread(null, argCount, &results) catch |e|
  {
    logLuaError(state);

    state.pop(1);
    return e;
  };

  if (code == .yield)
  {
    defer state.pop(1);

    const waitCondition: PausedThread.WaitCondition = @enumFromInt(
      state.toInteger(-1) catch
      {
        log.err(
          "Lua error: yield argument expected integer\n", .{}
        );

        return error.LuaRuntime;
      }
    );

    //log.debug("Coroutine yielded\n", .{});
    return .{.thread = state, .waitCondition = waitCondition};
  } else if (code == .ok)
  {
    //log.debug("Coroutine finished\n", .{});
    state.xMove(self, results);

    // Store the thread object in the registry using the thread pointer as a key
    std.debug.assert(state.getField(lua.registry_index, "fractal") == .table);
    std.debug.assert(state.getField(-1, "threads") == .table);
    state.pushLightUserdata(state);
    state.pushNil();
    state.setTable(-3);

    return null;
  }

  unreachable;
}

// Prints the error on top of the stack
pub fn logLuaError(state: *lua.Lua) void
{
  // Types are commented out if I can't think of a good way to log them
  switch (state.typeOf(-1))
  {
    .nil => log.err(
      "Lua error\n", .{}
    ),
    .boolean => log.err(
      "Lua error: {}\n", .{state.toBoolean(-1)}
    ),
    //.light_userdata => log.err(
    //  "Lua error: {}\n", .{}
    //),
    .number => log.err(
      "Lua error: {}\n", .{state.toNumber(-1) catch unreachable}
    ),
    .string => log.err(
      "Lua error: {s}\n", .{state.toString(-1) catch unreachable}
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
    else => log.err(
      "Lua error: Unknown error type: {}\n", .{state.typeOf(-1)}
    ),
  }
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

/// openWindow(minSize, windowModifiers)
/// This suspends the lua thread until the close input is sent
/// This function assumes it has been called from lua with exactly two operands
fn openWindow(self: *lua.Lua) !i32
{
  self.len(2);
  const windowModCount: usize = @intCast(self.toInteger(-1) catch
    self.raiseErrorStr(
      "Length operator of windowModifiers must return an integer",
      .{}
    ));
  self.pop(1);

  ui.currentWindow.pos = .{0, 0};

  const argBuffer =
    self.allocator().alloc(ui.Window.ElementArgument, windowModCount) catch
      self.raiseErrorStr("OutOfMemory", .{});
  var argCount: ui.Window.ElementIndex = 0;

  const top = self.getTop();
  for (1..windowModCount+1) |m|
  {
    defer self.setTop(top);

    if (self.getIndex(2, @intCast(m)) != .table)
    {
      self.raiseErrorStr(
        "Window modifier %d expected table, got %s",
        .{m, @tagName(self.typeOf(-1)).ptr}
      );
    }

    if (self.getIndex(-1, 1) != .string)
    {
      self.raiseErrorStr(
        "Window modifier %d expected string at index 1, got %s",
        .{m, @tagName(self.typeOf(-1)).ptr}
      );
    }

    const modifierType = self.toString(-1) catch unreachable;
    self.pop(1);

    // At this point, the modifier's table is on top of the stack
    switch (std.hash_map.hashString(modifierType))
    {
      std.hash_map.hashString("navigation") =>
      {
        const tblIdx = self.getTop();
        defer self.setTop(tblIdx);

        ui.currentWindow.inputs = .{
          // May need better default values for these
          .cursorUp =
            if (self.getField(tblIdx, "up") == .string)
              self.toString(-1) catch unreachable
            else "",
          .cursorDown = 
            if (self.getField(tblIdx, "down") == .string)
              self.toString(-1) catch unreachable
            else "",
          .cursorLeft = 
            if (self.getField(tblIdx, "left") == .string)
              self.toString(-1) catch unreachable
            else "",
          .cursorRight = 
            if (self.getField(tblIdx, "right") == .string)
              self.toString(-1) catch unreachable
            else "",
          .select = 
            if (self.getField(tblIdx, "select") == .string)
              self.toString(-1) catch unreachable
            else "",
          .back = 
            if (self.getField(tblIdx, "back") == .string)
              self.toString(-1) catch unreachable
            else "",
        };
      },
      std.hash_map.hashString("border") =>
      {
        self.len(-1);
        const defaultBorder = (self.toInteger(-1) catch unreachable) == 1;
        self.pop(1);

        ui.currentWindow.pos = .{1, 1};

        if (defaultBorder)
        {
          ui.currentWindow.border = .{
            .cornerCh = '*',
            .rowCh = '-',
            .colCh = '|'
          };
        } else
        {
          log.err("Custom borders not yet implemented\n", .{});
        }
      },
      std.hash_map.hashString("inventory") =>
      {
        if (self.getIndex(-1, 2) != .userdata)
        {
          self.raiseErrorStr(
            "Window modifier %d expected inventory at index 2, got %s",
            .{m, @tagName(self.typeOf(-1)).ptr}
          );
        }

        const inventoryObject = self.toUserdata(Object, -1) catch unreachable;
        const inventory =
          mainspace.ecs.getPtr(inventoryObject.id, "inventory", Inventory).?;

        argBuffer[argCount] = .{.Inventory = inventory};
        argCount += 1;
      },
      std.hash_map.hashString("text area") =>
      {
        if (self.getField(-1, "size") != .table)
        {
          self.raiseErrorStr(
            "Window modifier %d .size expected table, got %s",
            .{m, @tagName(self.typeOf(-1)).ptr}
          );
        }

        _ = self.getIndex(-1, 1);
        _ = self.getIndex(-2, 2);

        argBuffer[argCount] = .{.TextArea = .{
          .size = .{
            @intCast(self.toInteger(-2) catch
            {
              self.raiseErrorStr(
                "Window modifier %d index 2 expected integer at index 1, got %s",
                .{m, @tagName(self.typeOf(-2)).ptr}
              );
            }),
            @intCast(self.toInteger(-1) catch
            {
              self.raiseErrorStr(
                "Window modifier %d index 2 expected integer at index 2, got %s",
                .{m, @tagName(self.typeOf(-1)).ptr}
              );
            })
          },
          .initialData = &.{},
        }};

        // Clear position info
        self.pop(3);

        if (self.getField(-1, "text") == .string)
        {
          argBuffer[argCount].TextArea.initialData =
            try self.allocator().dupe(u8, self.toString(-1) catch unreachable);
        }

        argCount += 1;
      },
      else =>
      {
        self.raiseErrorStr(
          "Unknown window modifier \"%s\"",
          .{modifierType.ptr}
        );
      }
    }
  }

  ui.currentWindow.updateContents(
    self.allocator(), argBuffer[0..argCount]
  ) catch unreachable;

  self.allocator().free(argBuffer);

  if (!self.isTable(1))
  {
    self.raiseErrorStr(
      "Window minSize expected table, got %s",
      .{@tagName(self.typeOf(1)).ptr}
    );
  }

  // Discard the type result here because it doesn't give us float/integer information
  _ = self.getIndex(1, 1);
  _ = self.getIndex(1, 2);

  ui.currentWindow.size = @max(ui.currentWindow.size, graphics.Coord{
    @intCast(self.toInteger(-2) catch
    {
      self.raiseErrorStr(
        "Window minSize[1] expected integer, got %s",
        .{@tagName(self.typeOf(-2)).ptr}
      );
    }),
    @intCast(self.toInteger(-1) catch
    {
      self.raiseErrorStr(
        "Window minSize[2] expected integer, got %s",
        .{@tagName(self.typeOf(-1)).ptr}
      );
    })
  });

  self.pushInteger(@intFromEnum(PausedThread.WaitCondition.Window));
  self.yieldCont(1, 0, lua.wrap(openWindowContinuation));
}

fn openWindowContinuation(
  self: *lua.Lua, status: lua.Status, ctx: lua.Context) i32
{
  _ = status;
  _ = ctx;

  self.len(2);
  const windowModCount: usize = @intCast(self.toInteger(-1) catch
    self.raiseErrorStr(
      "Length operator of windowModifiers must return an integer",
      .{}
    ));
  self.pop(1);

  var elementIdx: u16 = 0;
  const top = self.getTop();
  for (1..windowModCount+1) |m|
  {
    defer self.setTop(top);

    if (self.getIndex(2, @intCast(m)) != .table)
    {
      self.raiseErrorStr(
        "Window modifier %d expected table, got %s",
        .{m, @tagName(self.typeOf(-1)).ptr}
      );
    }

    if (self.getIndex(-1, 1) != .string)
    {
      self.raiseErrorStr(
        "Window modifier %d expected string at index 1, got %s",
        .{m, @tagName(self.typeOf(-1)).ptr}
      );
    }

    const modifierType = self.toString(-1) catch unreachable;
    self.pop(1);

    // At this point, the modifier's table is on top of the stack
    switch (std.hash_map.hashString(modifierType))
    {
      std.hash_map.hashString("navigation") => {},
      std.hash_map.hashString("border") => {},
      std.hash_map.hashString("inventory") =>
      {
        elementIdx += 1;
      },
      std.hash_map.hashString("text area") =>
      {
        const textArea = ui.currentWindow.elements[elementIdx].TextArea;
        _ = self.pushString(
          @as([*]u8, &textArea.data)[0..textArea.size[0]*textArea.size[1]]
        );
        self.setField(-2, "text");

        elementIdx += 1;
      },
      else =>
      {
        self.raiseErrorStr(
          "Unknown window modifier \"%s\"",
          .{modifierType.ptr}
        );
      }
    }
  }

  self.pushValue(2);

  return 1;
}

/// Logs the stack of state
pub fn dumpStack(state: *lua.Lua) void
{
  var i = state.getTop();
  while (i > 0): (i -= 1)
  {
    log.debug("{}: ", .{i});
    printValue(state, i, 2);
    log.debug("\n", .{});
  }
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
    printValue(self, @intCast(arg), 4);
  }

  if (luaPrintEndsInNewline)
  {
    log.info("\n", .{});
  }
  
  return 0;
}

/// Prints the value at index in the lua stack
pub fn printValue(self: *lua.Lua, index: i32, maxDepth: u32) void
{
  const top: u31 = @intCast(self.getTop());
  // Reset the stack in case we're calling this from zig
  defer self.setTop(top);

  const i = self.absIndex(index);

  //self.checkStackErr(1, null);

  //self.setTop(argNum);
  switchBrk:switch (self.typeOf(i))
  {
    .table => {
      if (maxDepth == 0)
      {
        log.info("{{ ... }}", .{});

        break:switchBrk;
      }

      const revertNewline = luaPrintEndsInNewline;
      luaPrintEndsInNewline = false;
      defer if (revertNewline) {luaPrintEndsInNewline = true;};

      log.info("{{ ", .{});
      self.pushNil();

      var first = true;
      while (self.next(i))
      {
        // We don't want to add a comma the first time
        if (!first)
        {
          log.info(", ", .{});
        }
        first = false;

        printValue(self, -2, maxDepth - 1);
        log.info(" = ", .{});
        printValue(self, -1, maxDepth - 1);

        self.pop(1);
      }
      log.info(" }}", .{});
    },
    else => {
      const string = self.toStringEx(i);
      log.info("{s}", .{string});
      self.pop(1);
    }
  }
}

/// input() => "current input"
/// Polls for and reads the current input, returning it but not popping it
/// input(input) => bool
/// Returns if the current input equals the arg
pub const luaInput = lua.wrap(luaInputInner);

fn luaInputInner(state: *lua.Lua) !i32
{
  if (input.currentInput == null)
  {
    input.currentInput = input.getInput() orelse
    {
      state.pushInteger(@intFromEnum(PausedThread.WaitCondition.Input));
      state.yieldCont(1, 0, lua.wrap(luaInputContinuation));
    };
  }

  return try luaInputContinuation(state, .ok, 1);
}

fn luaInputContinuation(
  state: *lua.Lua,
  status: lua.Status,
  ctx: lua.Context) !i32
{
  _ = status;
  _ = ctx;

  std.debug.assert(input.currentInput != null);

  if (state.getTop() > 0)
  {
    const @"test" = try state.toString(1);
    const testIsInput = std.mem.eql(u8, input.currentInput.?, @"test");

    state.pushBoolean(testIsInput);
    if (testIsInput)
    {
      input.currentInput = null;
    }
  } else
  {
    _ = state.pushString(input.currentInput.?);
  }

  return 1;
}

/// prompt(string) => Input
/// Prompts the user with a string and returns the next input as a response
pub const luaPrompt = toApiFunction("fractal.prompt", luaPromptInner, .{});

fn luaPromptInner(state: *lua.Lua, prompt: []const u8) ![]const u8
{
  ui.currentWindow.pos = @splat(0);
  ui.currentWindow.inputs = null;
  ui.currentWindow.cursorIndex = 0;
  ui.currentWindow.border = .{.cornerCh = 0, .rowCh = 0, .colCh = 0};
  try ui.currentWindow.updateContents(
    state.allocator(),
    &.{
      .{.Text = .{.string = prompt}},
    }
  );
  if (input.currentInput == null)
  {
    input.currentInput = input.getInput() orelse
    {
      state.pushInteger(@intFromEnum(PausedThread.WaitCondition.Input));
      state.yieldCont(1, 0, lua.wrap(luaPromptContinuation));
    };
  }

  std.debug.assert(try luaPromptContinuation(state, .ok, 1) == 1);
  return state.toString(-1);
}

fn luaPromptContinuation(
  state: *lua.Lua,
  status: lua.Status,
  ctx: lua.Context) !i32
{
  _ = status;
  _ = ctx;

  std.debug.assert(input.currentInput != null);

  _ = state.pushString(input.currentInput.?);

  input.currentInput = null;

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

pub const luaTiles = struct
{
  parent: LevelHandle,

  /// self.tiles:get(pos) => {
  ///   id = integer,
  ///   mod = string,
  ///   name = string,
  ///   The returned table uses metamethods to allow directly modifying global typeData
  ///   typeData = function(self) => {
  ///     walkable = bool,
  ///     color = {"r" = float, "g" = float, "b" = float},
  ///     wallConnect = bool,
  ///     ch = string,
  ///   },
  ///   lua = function(self) => {...}
  /// }
  pub const get =
    toApiFunction("tiles:get", getInner, .{.resultOnStack = true});

  fn getInner(
    state: *lua.Lua,
    self: luaTiles,
    pos: Level.Coord) !i32
  {
    const tile = try Level.levels.items[self.parent.handle].getTile(pos);

    luaTile.fromTile(state, tile);

    return 1;
  }

  pub const luaTile = struct
  {
    id: ECS.Entity.Unmanaged,
    name: [:0]const u8,
    mod: [:0]const u8,

    /// Same as luaTiles.get, but generates the table from a tile
    pub fn fromTile(state: *lua.Lua, tile: Tile) void
    {
      const data = tile.getStaticData().?;
      
      state.createTable(0, 5);
      const returnTableIdx = state.absIndex(-1);

      state.pushInteger(tile.id);
      state.setField(returnTableIdx, "id");

      _ = state.pushString(data.name);
      state.setField(returnTableIdx, "name");
      _ = state.pushString(Mod.findTileMod(tile.type).name);
      state.setField(returnTableIdx, "mod");

      state.pushFunction(toApiFunction(
        "tile:typeData", luaTile.getStaticData, .{.resultOnStack = true}
      ));
      state.setField(returnTableIdx, "typeData");

      state.pushFunction(toApiFunction(
        "tile:lua", luaTile.getLuaTable, .{.resultOnStack = true}
      ));
      state.setField(returnTableIdx, "lua");
    }

    fn getStaticData(state: *lua.Lua, self: luaTile) i32
    {
      std.debug.assert(
        (state.getGlobal("fractal") catch unreachable) == .table
      );
      std.debug.assert(state.getField(-1, "mods") == .table);
      std.debug.assert(state.getField(-1, self.mod) == .table);
      std.debug.assert(state.getField(-1, "tiles") == .table);
      std.debug.assert(state.getField(-1, self.name) == .userdata);

      return 1;
    }

    fn getLuaTable(state: *lua.Lua, self: luaTile) i32
    {
      std.debug.assert(state.getField(lua.registry_index, "fractal") == .table);
      std.debug.assert(state.getField(-1, "modData") == .table);
      if (state.getIndex(-1, self.id) == .nil)
      {
        state.pop(1);

        state.createTable(0, 0);
        state.pushValue(-1);
        state.setIndex(-3, self.id);
      }

      return 1;
    }
  };

  pub const staticDataIndexMetamethod = toApiFunction(
    "tile.typeData.__index",
    staticDataIndexMetamethodInner,
    .{.resultOnStack = true}
  );
  fn staticDataIndexMetamethodInner(
    state: *lua.Lua,
    table: *Tile.Type,
    index: []const u8) i32
  {
    switch (std.hash_map.hashString(index))
    {
      std.hash_map.hashString("walkable") =>
      {
        state.pushBoolean(Tile.staticData.items[table.*].walkable);
      },
      std.hash_map.hashString("color") =>
      {
        // TODO: return a color table with its own metatable linking it with the color member
        unreachable;
      },
      std.hash_map.hashString("wallConnect") =>
      {
        state.pushBoolean(Tile.staticData.items[table.*].wallConnect);
      },
      std.hash_map.hashString("ch") =>
      {
        if (Tile.staticData.items[table.*].ch) |ch|
        {
          _ = state.pushString(@as(*const [1]u8, &ch));
        } else
        {
          std.debug.assert(state.getUserValue(1, 4) catch unreachable == .function);
        }
      },
      else => state.pushNil()
    }

    return 1;
  }

  pub const staticDataNewindexMetamethod = lua.wrap(
    staticDataNewindexMetamethodInner,
  );
  fn staticDataNewindexMetamethodInner(state: *lua.Lua)
    error{InvalidIndex, InvalidValueType}!i32
  {
    const table = state.toUserdata(Tile.Type, 1) catch unreachable;
    const index = state.toString(2) catch return error.InvalidIndex;

    switch (std.hash_map.hashString(index))
    {
      std.hash_map.hashString("walkable") =>
      {
        const value = state.toBoolean(3);

        Tile.staticData.items[table.*].walkable = value;
      },
      std.hash_map.hashString("color") =>
      {
        // TODO: return a color table with its own metatable linking it with the color member
        unreachable;
      },
      std.hash_map.hashString("wallConnect") =>
      {
        const value = state.toBoolean(3);

        Tile.staticData.items[table.*].wallConnect = value;
      },
      std.hash_map.hashString("ch") =>
      {
        if (state.isFunction(3))
        {
          state.pushValue(3);
          state.setUserValue(1, 4) catch unreachable;

          Tile.staticData.items[table.*].ch = null;
        } else
        {
          const value = state.toString(3) catch return error.InvalidValueType;

          Tile.staticData.items[table.*].ch =
            if (value.len > 0) value[0] else ' ';
        }
      },
      else => return error.InvalidIndex,
    }

    return 0;
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
  
  fn removeInner(self: luaTiles, pos: Level.Coord) bool
  {
    return Level.levels.items[self.parent.handle].tiles.swapRemove(pos);
  }
  
  /// self.tiles:count() => int
  /// Returns size of level's tilemap
  pub const count = toApiFunction("tiles:count", countInner, .{});
  
  fn countInner(self: luaTiles) u32
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

          state.createTable(0, 3);
  
          state.pushValue(objectTableIdx);
          state.setField(-2, "parent");

          state.pushFunction(toApiFunction(
            "object.sight:inView",
            struct {fn inView(
              self: struct {parent: struct {id: ECS.Entity.Unmanaged}},
              pos: Level.Coord) !bool
            {
              const objectId: ECS.Entity.Managed = .{
                .parent = &mainspace.ecs,
                .id = self.parent.id,
              };
  
              const sight = objectId.get("sight", Sight) orelse
                return error.InvalidComponent;
  
              return sight.inView(pos);
            }}.inView, .{}
          ));
          state.setField(-2, "inView");

          state.pushFunction(toApiFunction(
            "object.sight:draw",
            struct {fn draw(
              self: struct {parent: struct {id: ECS.Entity.Unmanaged}}) !void
            {
              const objectId: ECS.Entity.Managed = .{
                .parent = &mainspace.ecs,
                .id = self.parent.id,
              };
  
              if (objectId.get("sight", Sight) == null)
              {
                return error.InvalidComponent;
              }

              try Level.sightToDraw.append(Level.gpa, objectId.id);
  
              return;
            }}.draw, .{}
          ));
          state.setField(-2, "draw");

          state.setField(objectTableIdx, "sight");
        },
        std.hash_map.hashString(@typeName(TileMemory)) =>
        {
          if (ecs.get(object.id, arr.key_ptr.*, TileMemory) == null)
          {
            break;
          }

          state.createTable(0, 2);
  
          state.pushValue(objectTableIdx);
          state.setField(-2, "parent");

          state.pushFunction(toApiFunction(
            "object.memory:draw",
            struct {fn draw(
              self: struct {parent: struct {id: ECS.Entity.Unmanaged}}) !void
            {
              const objectId: ECS.Entity.Managed = .{
                .parent = &mainspace.ecs,
                .id = self.parent.id,
              };
  
              if (objectId.get("tileMemory", TileMemory) == null)
              {
                return error.InvalidComponent;
              }

              try Level.memoryToDraw.append(Level.gpa, objectId.id);
  
              return;
            }}.draw, .{}
          ));
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
    var args: std.meta.ArgsTuple(@TypeOf(function)) =
      undefined;

    var i: u32 = 0;
    inline for (&args) |*arg|
    {
      // Give special access to lua environment
      if (@TypeOf(arg.*) == *lua.Lua)
      {
        arg.* = self;
        continue;
      }
      i += 1;

      arg.* = self.toAny(@TypeOf(arg.*), @intCast(i)) catch |e|
      blk:{
        if (@errorReturnTrace()) |trace|
        {
          std.debug.dumpErrorReturnTrace(trace);
        }
        // toAny gives an error with optional void pointers, so here
        if (e != error.ExpectedUserdata)
        {
          self.raiseErrorStr(
            "%s arg %I expected type %s, got %s: %s",
            .{
              name.ptr,
              i,
              @typeName(@TypeOf(arg.*)),
              @tagName(self.typeOf(@intCast(i))).ptr,
              @errorName(e).ptr
            }
          );
        } else
        {
          break:blk switch (@typeInfo(@TypeOf(arg.*)))
          {
            .@"union", .pointer => unreachable,
            else => std.mem.zeroes(@TypeOf(arg.*))
          };
        }
      };
    }

    if (self.getTop() < i)
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

const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Timestamp = Io.Timestamp;

const builtin = @import("builtin");

pub const nc = @cImport({@cInclude("ncurses.h");});
pub const sdl = @cImport({
  @cInclude("SDL3/SDL.h");
  @cInclude("SDL3_image/SDL_image.h");
});

const directories = @import("directories.zig");
const luaUtil = @import("lua.zig");
const Mod = @import("mod.zig");
const logger = @import("debug_log_fn.zig");
const input = @import("input.zig");
const graphics = @import("graphics.zig");

const ECS = @import("ecs");

//const appdata = @import("appdata.zig");
const Turn = @import("turn.zig");
const Scene = @import("scene.zig");
const Level = @import("scenes/level.zig");
const Level_0 = @import("levels/level_0.zig");
const Object = @import("object.zig");
const Player = @import("player.zig");
const Overtime = @import("overtime.zig");
const Sight = @import("sight.zig");
const TileMemory = @import("tile_memory.zig");

const StartOptions = struct {
  useTerminal: ?bool = null,
  useWindow: ?bool = null,

  /// What is even this
  logFile: [Io.Dir.max_path_bytes]u8 =
    ("log.log" ++ (.{undefined} ** (Io.Dir.max_path_bytes-"log.log".len))).*,
  logFileLen: usize = "log.log".len,
};

pub const std_options = std.Options{
  .logFn = logger.debugLogFN,
};

pub var randomEngine = std.Random.DefaultPrng.init(0);
pub var rand = randomEngine.random();

/// I want to avoid using this, there are some functions where I can't pass an allocator down so we need this
pub var allocator: std.mem.Allocator = undefined;

pub var ecs: ECS = undefined;

pub var startTime: Timestamp = undefined;

pub var running: bool = true;

pub fn main(init: std.process.Init) !void
{
  startTime = .now(init.io, .awake);

  const options = try handleArgs(init.minimal.args, init.gpa) orelse return;
  @memcpy(
    logger.logFilePath[0..options.logFileLen],
    options.logFile[0..options.logFileLen]
  );
  logger.logFilePathLen = options.logFileLen;

  log.info("Entered main function\n", .{});

  allocator = init.gpa;
    
  ecs = .init(init.gpa);
  defer ecs.deinit();

  randomEngine.seed(@bitCast(startTime.toMilliseconds()));
  rand = randomEngine.random();

  directories.initSearchPaths(init.io);
  try Mod.loadAll(init.io, init.gpa);
  defer Mod.unloadAll(init.gpa, false);

  for (Scene.scenes.values) |scene|
  {
    _ = try scene.init(init.gpa);
  }

  defer for (Scene.scenes.values) |scene|
  {
    // The level scene's deinit function is invalid
    if (scene.id == .Level)
    {
      continue;
    }

    scene.deinit() catch unreachable;
  };

  //for (Level.levels.items) |level|
  //{
  //  _ = try level.scene.init(init.gpa);
  //}

  defer Level.interface.deinit() catch unreachable;
  defer for (Level.levels.items) |*level|
  {
    Level.deinit(level);
  };

  // TODO: Add small chance of levels 1 or 2
  // TODO: Remove currentLevel, instead use the level coordinate of player
  // TODO: Move this logic to base mod (set player position to level on mod init)
  Level.currentLevel = 0;

  defer Turn.queue.deinit(init.gpa);

  defer ecs.getPtr(
    Level.objects.items[0].id, "tileMemory", TileMemory
  ).?.tiles.deinit(init.gpa);
  defer ecs.getPtr(
    Level.objects.items[0].id, "sight", Sight
  ).?.view.deinit(init.gpa);

  //log.info("Initialized player as entity {}\n", .{Level.objects.items[0]});

  Scene.currentScene = Scene.scenes.get(.Level);
  _ = try Scene.currentScene.enter();

  try graphics.init(init.gpa, options.useTerminal, options.useWindow, null);
  defer graphics.deinit();

  //var frameStart = Timestamp.zero;
  while (running)
  {
    //const newFrame = Timestamp.now(init.io, .awake);
    //const frameTime: f64 =
    //  @floatFromInt(frameStart.durationTo(newFrame).toMicroseconds());
    //frameStart = newFrame;
    //log.info("FPS: {} ({})\n", .{std.time.us_per_s / frameTime, frameTime});

    var componentIt = ecs.componentTable.iterator();
    while (componentIt.next()) |component|
    {
      if (!std.mem.eql(u8, component.value_ptr.typeID, @typeName(Overtime)))
      {
        continue;
      }

      for (ecs.getArr(component.key_ptr.*, Overtime).?) |*overtime|
      {
        overtime.update();
        //log.debug("Component {s} updated to {}\n", .{component.key_ptr.*, overtime.value});
      }
    }

    try Scene.currentScene.update();

    if (Mod.luaEnv) |luaState|
    {
      const top = luaState.getTop();
      defer luaState.setTop(top);

      std.debug.assert(try luaState.getGlobal("fractal") == .table);
      std.debug.assert(luaState.getField(-1, "mods") == .table);

      for (Mod.mods.items) |mod|
      {
        _ = luaState.pushString(mod.name);
        std.debug.assert(luaState.getTable(-2) == .table);
        std.debug.assert(luaState.getField(-1, "update") == .function);

        luaState.pushValue(-2);
        try luaUtil.runFunction(luaState, .{.args = 1});
      }
    }

    //log.info("Start frame\n", .{});
    try graphics.startFrame();

    Scene.currentScene.draw() catch |e| switch (e)
    {
      graphics.Error.RenderFail => log.warn("Frame failed to render\n", .{}),
      else => return e,
    };

    try graphics.endFrame();
  }

  log.info("Exited main function\n", .{});

//  try appdata.saveState();
}

const ArgError = error{MissingArgument};
fn handleArgs(args: std.process.Args, gpa: Allocator)
  (ArgError || Allocator.Error)!?StartOptions
{
  var result = StartOptions{};

  var it = try args.iterateAllocator(gpa);
  defer it.deinit();
  while (it.next()) |arg|
  {
    if ((std.mem.find(u8, arg, "-h") orelse 2) < 2)
    {
      std.debug.print(
        \\The Broken Fractal - A roguelike based off of the backrooms
        \\
        \\Usage:
        \\  fractal [options]
        \\
        \\Options:
        \\  -h, --help                   Show this help text
        \\  -t, --terminal [=true|false] Force running through a TTY with ANSI escape codes
        \\  -w, --window   [=true|false] Force running through a graphical window
        \\  -l, --log-file <=| > <file>  Override logging output file (default ./log.log)
        \\
        \\Examples:
        \\
        \\  Show this help text:
        \\    fractal -h
        \\
        \\  Launch exclusively through a terminal:
        \\    fractal --terminal=true --window=false
        \\
        \\  Launch headless:
        \\    fractal --terminal=false --window=false
        \\
      , .{});
      return null;
    }

    if ((std.mem.find(u8, arg, "-t") orelse 2) < 2)
    {
      if (std.mem.find(u8, arg, "=false") != null)
      {
        result.useTerminal = false;
      } else
      {
        result.useTerminal = true;
      }
    }

    if ((std.mem.find(u8, arg, "-w") orelse 2) < 2)
    {
      if (std.mem.find(u8, arg, "=false") != null)
      {
        result.useWindow = false;
      } else
      {
        result.useWindow = true;
      }
    }

    if ((std.mem.find(u8, arg, "-l") orelse 2) < 2)
    {
      if (std.mem.find(u8, arg, "=")) |pos|
      {
        @memcpy(result.logFile[0..arg.len-pos-1], arg[pos+1..arg.len]);
        result.logFileLen = arg.len-pos-1;
      } else if (it.next()) |path|
      {
        @memcpy(result.logFile[0..path.len], path);
        result.logFileLen = path.len;
      } else
      {
        return error.MissingArgument;
      }
    }
  }

  return result;
}

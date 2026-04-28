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
const mod = @import("mod.zig");
const logger = @import("debug_log_fn.zig");
const input = @import("input.zig");
const graphics = @import("graphics.zig");

const ECS = @import("ecs");

//const appdata = @import("appdata.zig");
const Scene = @import("scene.zig");
const Level = @import("scenes/level.zig");
const Level_0 = @import("levels/level_0.zig");
const Object = @import("object.zig");
const Player = @import("player.zig");
const Sight = @import("sight.zig");
const TileMemory = @import("tile_memory.zig");

const StartOptions = struct {
  useTerminal: ?bool = null,
  useWindow: ?bool = null,
};

pub const std_options = std.Options{
  .logFn = logger.debugLogFN,
};

pub var randomEngine = std.Random.DefaultPrng.init(0);
pub var rand = randomEngine.random();

//pub var allocator = std.heap.GeneralPurposeAllocator(.{}).init;

pub var ecs: ECS = undefined;

pub var startTime: Timestamp = undefined;

pub var running: bool = true;

pub fn main(init: std.process.Init) !void
{
  startTime = .now(init.io, .awake);// catch switch (builtin.os.tag)
  //{
  //  .windows, .uefi, .wasi => .{
  //    .started = .{.timestamp = 0}, .previous = .{.timestamp = 0}
  //  },
  //  else => unreachable,
  //};
  log.info("Entered main function\n", .{});
    
  const options = try handleArgs(init.minimal.args, init.gpa) orelse return;

  ecs = .init(init.gpa);
  defer ecs.deinit();

  randomEngine.seed(@bitCast(startTime.toMilliseconds()));
  rand = randomEngine.random();

  directories.initSearchPaths(init.io);
  try mod.loadAll(init.io);
  defer mod.unloadAll(init.io);

  for (Scene.scenes.values) |scene|
  {
    // The level scene's init function is invalid
    if (scene.id == .Level)
    {
      continue;
    }

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

  for (Level.levels.values) |level|
  {
    _ = try level.scene.init(init.gpa);
  }

  defer for (Level.levels.values) |level|
  {
    level.scene.deinit() catch unreachable;
  };

  // TODO: Add small chance of levels 1 or 2
  Level.currentLevel = Level.levels.get(.Level0);

  try Level.objects.append(init.gpa, .init(.Player, .{0, 0}, .{
    .sight = Sight{.radius = 15, .view = .empty},
    .tileMemory = TileMemory{.tiles = .empty},
  }));

  defer ecs.getPtr(
    Level.objects.items[0].id, "tileMemory", TileMemory
  ).?.tiles.deinit(init.gpa);
  defer ecs.getPtr(
    Level.objects.items[0].id, "sight", Sight
  ).?.view.deinit(init.gpa);

  log.info("Initialized player as entity {}\n", .{Level.objects.items[0]});

  Scene.currentScene = Scene.scenes.get(.Level);
  _ = try Scene.currentScene.enter();

  try graphics.init(init.gpa, options.useTerminal, options.useWindow, null);
  defer graphics.deinit();

  while (running)
  {
    try input.getInput(init.io);
    
    try Scene.currentScene.update();

    log.info("Start frame\n", .{});
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

fn handleArgs(args: std.process.Args, allocator: Allocator)
  Allocator.Error!?StartOptions
{
  var result = StartOptions{};

  var it = try args.iterateAllocator(allocator);
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
  }

  return result;
}

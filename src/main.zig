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

pub const level = &Level_0.level;

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
    
  const options = try handleArgs(init.minimal.args, init.gpa) orelse return;

  ecs = .init(init.gpa);
  defer ecs.deinit();

  log.info("Entered main function\n", .{});

  randomEngine.seed(@bitCast(startTime.toMilliseconds()));
  rand = randomEngine.random();

  for (Scene.scenes.values) |scene|
  {
    _ = try scene.init(init.gpa);
  }

  defer for (Scene.scenes.values) |scene|
  {
    scene.deinit() catch unreachable;
  };

  level.objectCount = 1;
  level.objects[0] = ecs.addEntityUnmanaged(.{
    .objectType = Object.Type.Player,
    .pos = Level.Coord{0, 0},
    .sight = Sight{.radius = 15, .view = .init(init.gpa)},
    .tileMemory = TileMemory{.tiles = .empty},
  });
  log.info("Initialized player as entity {}\n", .{level.objects[0]});

  Scene.currentScene = try Scene.scenes.get(.Level).enter();

  graphics.init(options.useTerminal, options.useWindow, null);
  defer graphics.deinit();

  while (running)
  {
    try input.getInput(init.io);
    
    try Scene.currentScene.update();

    try graphics.startFrame();

    try Scene.currentScene.draw();

    try graphics.endFrame();
  }

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

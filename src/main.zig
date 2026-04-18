const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;
const time = std.time;

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

pub const level = &Level_0.level;

pub const std_options = std.Options{
  .logFn = logger.debugLogFN,
};

pub var randomEngine = std.Random.DefaultPrng.init(0);
pub var rand = randomEngine.random();

pub var allocator = std.heap.GeneralPurposeAllocator(.{}).init;

pub var ecs: ECS = undefined;

pub var timer: time.Timer = undefined;

pub var running: bool = true;

pub fn main() !void
{
  timer = time.Timer.start() catch switch (builtin.os.tag)
  {
    .windows, .uefi, .wasi => .{
      .started = .{.timestamp = 0}, .previous = .{.timestamp = 0}
    },
    else => unreachable,
  };

  ecs = .init(allocator.allocator());
  defer ecs.deinit();

  log.info("Entered main function\n", .{});

  randomEngine.seed(@intCast(time.timestamp()));
  rand = randomEngine.random();

  for (Scene.scenes.values) |scene|
  {
    _ = try scene.init(allocator.allocator());
  }

  defer for (Scene.scenes.values) |scene|
  {
    scene.deinit() catch unreachable;
  };

  level.objectCount = 1;
  level.objects[0] = ecs.addEntityUnmanaged(.{
    .objectType = Object.Type.Player,
    .pos = Level.Coord{0, 0},
    .sight = Sight{.radius = 15, .view = .init(allocator.allocator())},
    .tileMemory = TileMemory{.tiles = .init(allocator.allocator())},
  });
  log.info("Initialized player as entity {}\n", .{level.objects[0]});

  Scene.currentScene = try Scene.scenes.get(.Level).enter();

  graphics.init(true, null, null);
  defer graphics.deinit();

  while (running)
  {
    try input.getInput();
    
    try Scene.currentScene.update();

    try graphics.startFrame();

    try Scene.currentScene.draw();

    try graphics.endFrame();
  }

//  try appdata.saveState();
}

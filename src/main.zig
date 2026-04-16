const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;

pub const nc = @cImport({@cInclude("ncurses.h");});

pub fn acs(ch: nc.chtype) nc.chtype
{
  return 0x400000 + ch;
}

const logger = @import("debug_log_fn.zig");
const input = @import("input_handler.zig");

const ECS = @import("ecs");

const appdata = @import("appdata.zig");
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

pub var running: bool = true;

pub fn main() !void
{
  ecs = .init(allocator.allocator());
  defer ecs.deinit();

  log.info("Entered main function\n", .{});

  randomEngine.seed(@intCast(std.time.timestamp()));
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

  var err: c_int = nc.OK;
  defer if (err != nc.OK) log.err("ncurses function failed\n", .{});

  _ = nc.initscr() orelse {err = nc.ERR;};
  err |= nc.raw();
  err |= nc.nodelay(nc.stdscr, true);
  err |= nc.noecho();
  err |= nc.keypad(nc.stdscr, true);
  err |= nc.curs_set(0);
  defer err |= nc.endwin();

  if (nc.can_change_color())
  {
    err |= nc.start_color();
  }

  while (running)
  {
    try input.getInput();
    
    try Scene.currentScene.update();

    err |= nc.erase();

    try Scene.currentScene.draw();

    err |= nc.refresh();
  }

  try appdata.saveState();
}

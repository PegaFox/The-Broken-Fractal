const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;

const ncurses = @cImport({@cInclude("ncurses.h");});

const logger = @import("debug_log_fn.zig");
const input = @import("input_handler.zig");

const ECS = @import("ecs");

const Scene = @import("scenes/scene.zig");
const World = @import("world.zig");
const Object = @import("object.zig");
const Player = @import("player.zig");

pub const std_options = std.Options{
  .logFn = logger.debugLogFN,
};

pub var randomEngine = std.Random.DefaultPrng.init(0);
pub var rand = randomEngine.random();

pub var mainGPAllocator = std.heap.GeneralPurposeAllocator(.{}).init;
pub var mainAllocator = mainGPAllocator.allocator();

pub var ecs: ECS = undefined;

pub var scene: *Scene = undefined;
pub var world: World = undefined;
pub var worldBuffer: [World.minBufferSize()]u8 = undefined;

pub var running: bool = true;

pub fn main() !void
{
  ecs = .init(mainAllocator);
  defer ecs.deinit();

  log.info("Entered main function\n", .{});

  _ = ncurses.initscr();
  _ = ncurses.raw();
  _ = ncurses.nodelay(ncurses.stdscr, true);
  _ = ncurses.noecho();
  _ = ncurses.keypad(ncurses.stdscr, true);
  _ = ncurses.curs_set(0);
  defer _ = ncurses.endwin();

  randomEngine.seed(@intCast(std.time.timestamp()));
  rand = randomEngine.random();

  var fba = std.heap.FixedBufferAllocator.init(&worldBuffer);
  world = World.init(fba.allocator(), -@divFloor(@Vector(2, i16){@intCast(ncurses.COLS), @intCast(ncurses.LINES)}, World.Coord{2, 2}));
  world.objects[0] = ecs.addEntity(&.{"objectType", "pos"}, .{Object.Type.Player, World.Coord{0, 0}});

  scene = Scene.world.enter(&Scene.world);

  while (running)
  {
    input.getInput();
    
    scene.update(scene);

    scene.draw(scene);
  }
}

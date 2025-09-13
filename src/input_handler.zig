const std = @import("std");
const log = std.log;

const ncurses = @cImport({@cInclude("ncurses.h");});

const Player = @import("player.zig");
const World = @import("world.zig");
const mainspace = @import("main.zig");

pub fn getInput() void
{
  const key: c_int = ncurses.getch();

  if (key != -1)
  {
    log.debug("{}\n", .{key});
  }

  switch (key)
  {
    3, 26 => mainspace.running = false,
    ncurses.KEY_RESIZE => {
      const pos = mainspace.ecs.getComponent(mainspace.world.objects[0].?, "pos", World.Coord).?;
      mainspace.world.camPos = pos-@divFloor(@Vector(2, i16){@intCast(ncurses.COLS), @intCast(ncurses.LINES)}, World.Coord{2, 2});
    },
    else => {},
  }

  mainspace.scene.getInput(mainspace.scene, key);
}

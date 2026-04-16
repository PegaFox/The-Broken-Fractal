const std = @import("std");
const log = std.log;

const Scene = @import("scene.zig");

const Level = @import("level.zig");
const mainspace = @import("main.zig");
const nc = mainspace.nc;

pub fn getInput() !void
{
  const key: c_int = nc.getch();

  if (key != -1)
  {
    //log.debug("{}\n", .{key});
  }

  switch (key)
  {
    3, 26 => mainspace.running = false,
    nc.KEY_RESIZE => {
      //const pos = mainspace.ecs.getComponent(
      //  mainspace.level.objects[0], "pos", Level.Coord
      //).?;
      //mainspace.level.camPos = pos-@divFloor(
      //  @Vector(2, i16){@intCast(nc.COLS), @intCast(nc.LINES)},
      //  Level.Coord{2, 2}
      //);
    },
    else => {},
  }

  try Scene.currentScene.getInput(key);
}

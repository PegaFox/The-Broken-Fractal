const std = @import("std");
const log = std.log;
const ncurses = @cImport({@cInclude("ncurses.h");});
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
    'h', ncurses.KEY_LEFT => mainspace.player.move(&mainspace.world, .{-1, 0}),
    'y', ncurses.KEY_HOME => mainspace.player.move(&mainspace.world, .{-1, -1}),
    'j', ncurses.KEY_DOWN => mainspace.player.move(&mainspace.world, .{0, 1}),
    'b', ncurses.KEY_END => mainspace.player.move(&mainspace.world, .{-1, 1}),
    'k', ncurses.KEY_UP => mainspace.player.move(&mainspace.world, .{0, -1}),
    'u', 339 => mainspace.player.move(&mainspace.world, .{1, -1}),
    'l', ncurses.KEY_RIGHT => mainspace.player.move(&mainspace.world, .{1, 0}),
    'n', 338 => mainspace.player.move(&mainspace.world, .{1, 1}),
    'W', => {},
    else => {},
  }

}

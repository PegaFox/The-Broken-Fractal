const Self = @This();

const ncurses = @cImport({@cInclude("ncurses.h");});

const World = @import("world.zig");
const Tile = @import("tile.zig");
const Object = @import("object.zig");
const mainspace = @import("main.zig");

pub fn displayInfo(message: []const u8) void
{
  _ = ncurses.mvaddnstr(1, 1, message.ptr, message.len);
}

pub fn prompt(message: []const u8) i32
{
  _ = ncurses.timeout(-1);

  displayInfo(message);
  const result: i32 = ncurses.getch();

  _ = ncurses.timeout(0);

  return result;
}

pub fn move(self: *Self, world: *World, offset: @Vector(2, i16)) void
{
  if (Tile.getStaticData(world.getTile(@bitCast(self.parent.pos+offset))).?.walkable)
  {
    self.parent.pos += offset;
    world.camPos += offset;

    for (0..3) |y|
    {
      for (0..3) |x|
      {
        _ = world.getTile(self.parent.pos+@Vector(2, i16){@as(i16, @intCast(x)), @as(i16, @intCast(y))}-@Vector(2, i16){1, 1});
      }
    }
  }
}

pub fn write(world: *World) void
{
  const response = prompt("What to write on? (direction key)");

  const dir: @Vector(2, i16) = switch (response)
  {
    'h', ncurses.KEY_LEFT => .{-1, 0},
    'y', ncurses.KEY_HOME => .{-1, -1},
    'j', ncurses.KEY_DOWN => .{0, 1},
    'b', ncurses.KEY_END => .{-1, 1},
    'k', ncurses.KEY_UP => .{0, -1},
    'u', 339 => .{1, -1},
    'l', ncurses.KEY_RIGHT => .{1, 0},
    'n', 338 => .{1, 1},
    '.' => .{0, 0},
    else => null
  } orelse return;

  
}

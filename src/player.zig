const Self = @This();

const ncurses = @cImport({@cInclude("ncurses.h");});

const Scene = @import("scenes/scene.zig");
const WritingScene = @import("scenes/writing.zig");
const World = @import("world.zig");
const Tile = @import("tile.zig");
const Object = @import("object.zig");
const mainspace = @import("main.zig");

pub fn displayInfo(message: []const u8) void
{
  _ = ncurses.mvaddnstr(1, 1, message.ptr, @intCast(message.len));
}

pub fn prompt(message: []const u8) i32
{
  _ = ncurses.timeout(-1);
  defer _ = ncurses.timeout(0);

  displayInfo(message);
  const result: i32 = ncurses.getch();

  return result;
}

pub fn move(world: *World, offset: World.Coord) void
{
  const pos = mainspace.ecs.getComponentPtr(world.objects[0].?, "pos", World.Coord).?;
  if (Tile.getStaticData(world.getTile(@bitCast(pos.*+offset))).?.walkable)
  {
    pos.* += offset;
    world.camPos += offset;

    for (0..3) |y|
    {
      for (0..3) |x|
      {
        _ = world.getTile(pos.*+World.Coord{@as(i16, @intCast(x)), @as(i16, @intCast(y))}-World.Coord{1, 1});
      }
    }
  }
}

pub fn write(world: *World) void
{
  const response = prompt("What to write on? (direction key)");

  const dir = switch (response)
  {
    'h', ncurses.KEY_LEFT => World.Coord{-1, 0},
    'y', ncurses.KEY_HOME => World.Coord{-1, -1},
    'j', ncurses.KEY_DOWN => World.Coord{0, 1},
    'b', ncurses.KEY_END => World.Coord{-1, 1},
    'k', ncurses.KEY_UP => World.Coord{0, -1},
    'u', ncurses.KEY_PPAGE => World.Coord{1, -1},
    'l', ncurses.KEY_RIGHT => World.Coord{1, 0},
    'n', ncurses.KEY_NPAGE => World.Coord{1, 1},
    '.', ncurses.KEY_BEG => World.Coord{0, 0},
    else => return,
  };

  const selectedTile = world.getTile(mainspace.ecs.getComponent(world.objects[0].?, "pos", World.Coord).? + dir);

  mainspace.ecs.getComponentPtr(selectedTile, "sprite", Tile.Sprite).?.* = '~';

  WritingScene.writingBuffer = (mainspace.ecs.getComponentPtr(selectedTile, "markings", [64]u8) orelse blk: {
    mainspace.ecs.addEntityComponent(selectedTile, "markings", @as([64]u8, .{' '} ** 64));
    break :blk mainspace.ecs.getComponentPtr(selectedTile, "markings", [64]u8);
  }).?[0..];

  WritingScene.bufferWidth = 8;

  mainspace.scene.exit(mainspace.scene);
  mainspace.scene = Scene.writing.enter(&Scene.writing);
}

const Self = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const graphics = @import("graphics.zig");

const Scene = @import("scene.zig");
const WritingScene = @import("scenes/writing.zig");
const Level = @import("scenes/level.zig");
const Tile = @import("tile.zig");
const Object = @import("object.zig");
const mainspace = @import("main.zig");
const nc = mainspace.nc;

pub fn displayInfo(message: []const u8) graphics.Error!void
{
  try graphics.drawStr(.{1, 1}, message);
  //_ = nc.mvaddnstr(1, 1, message.ptr, @intCast(message.len));
}

pub fn prompt(message: []const u8) graphics.Error!i32
{
  _ = nc.timeout(-1);
  defer _ = nc.timeout(0);

  try displayInfo(message);
  const result: i32 = nc.getch();

  return result;
}

pub fn move(level: *Level, offset: Level.Coord) Allocator.Error!void
{
  const pos =
    mainspace.ecs.getPtr(Level.objects.items[0].id, "pos", Level.Coord).?;
  if (Tile.getStaticData(try level.getTile(@bitCast(pos.*+offset))).?.walkable)
  {
    pos.* += offset;
    //level.camPos += offset;

    //for (0..3) |y|
    //{
    //  for (0..3) |x|
    //  {
    //    _ = try level.getTile(
    //      pos.* +
    //      Level.Coord{@as(i16, @intCast(x)), @as(i16, @intCast(y))} -
    //      Level.Coord{1, 1}
    //    );
    //  }
    //}
  }
}

pub fn write(level: *Level) !void
{
  const response = try prompt("What to write on? (direction key)");

  const dir = switch (response)
  {
    'h', nc.KEY_LEFT => Level.Coord{-1, 0},
    'y', nc.KEY_HOME => Level.Coord{-1, -1},
    'j', nc.KEY_DOWN => Level.Coord{0, 1},
    'b', nc.KEY_END => Level.Coord{-1, 1},
    'k', nc.KEY_UP => Level.Coord{0, -1},
    'u', nc.KEY_PPAGE => Level.Coord{1, -1},
    'l', nc.KEY_RIGHT => Level.Coord{1, 0},
    'n', nc.KEY_NPAGE => Level.Coord{1, 1},
    '.', nc.KEY_BEG => Level.Coord{0, 0},
    else => return,
  };

  const selectedTile = try level.getTile(
    mainspace.ecs.get(Level.objects.items[0].id, "pos", Level.Coord).? + dir
  );

  mainspace.ecs.getComponentPtr(selectedTile, "sprite", Tile.Sprite).?.* = '~';

  WritingScene.writingBuffer =
    (mainspace.ecs.getComponentPtr(selectedTile, "markings", [64]u8) orelse blk:
    {
      mainspace.ecs.addEntityComponent(
        selectedTile, "markings", @as([64]u8, .{' '} ** 64)
      );
      break :blk
        mainspace.ecs.getComponentPtr(selectedTile, "markings", [64]u8);
    }).?[0..];

  WritingScene.bufferWidth = 8;

  try Scene.currentScene.exit();
  Scene.currentScene = try Scene.scenes.get(.Writing).enter();
}

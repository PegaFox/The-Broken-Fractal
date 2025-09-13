const Self = @This();

const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;
const ArrayHashMap = std.AutoArrayHashMap;

const ncurses = @cImport({@cInclude("ncurses.h");});

const ECS = @import("ecs");
const Tile = @import("tile.zig");
const Object = @import("object.zig");
const mainspace = @import("main.zig");

pub fn minBufferSize() usize
{
  return 4_096;
}

pub const Coord = @Vector(2, i16);

const Tilemap: type = ArrayHashMap(Coord, ECS.Entity);

tiles: Tilemap,

objects: [16]?ECS.Entity = .{null} ** 16,
camPos: Coord,

currentTile: ECS.Entity = undefined, 

pub fn init(allocator: Allocator, camPos: Coord) Self
{
  return .{
    .tiles = Tilemap.init(allocator),
    .camPos = camPos,
  };
}

pub fn generateTile(self: *Self, pos: Coord) ECS.Entity
{
  var result: ECS.Entity = undefined;
  //Tile.init(Tile, null) catch |e| blk: {log.err("Tile allocation returned {}", .{e}); break :blk &self.currentTile;};

  if (@abs(@rem(pos[0], 2)) == 1 and @abs(@rem(pos[1], 2)) == 1)
  {
    result = mainspace.ecs.addEntity(&.{"tileType", "sprite", "color"}, .{Tile.Type.CyanideCarpet, @as(Tile.Sprite, '.'), Tile.Color{.red = 255, .green = 255, .blue = 255}});
  } else if (@rem(pos[0], 2) == 0 and @rem(pos[1], 2) == 0)
  {
    result = mainspace.ecs.addEntity(&.{"tileType", "sprite", "color"}, .{Tile.Type.YellowWallpaper, @as(Tile.Sprite, '+'), Tile.Color{.red = 255, .green = 255, .blue = 255}});
  } else
  {
    if (mainspace.rand.boolean())
    {
      if (@rem(pos[0], 2) == 0)
      {
        result = mainspace.ecs.addEntity(&.{"tileType", "sprite", "color"}, .{Tile.Type.YellowWallpaper, @as(Tile.Sprite, '|'), Tile.Color{.red = 255, .green = 255, .blue = 255}});
      } else
      {
        result = mainspace.ecs.addEntity(&.{"tileType", "sprite", "color"}, .{Tile.Type.YellowWallpaper, @as(Tile.Sprite, '-'), Tile.Color{.red = 255, .green = 255, .blue = 255}});
      }
    } else
    {
      result = mainspace.ecs.addEntity(&.{"tileType", "sprite", "color"}, .{Tile.Type.CyanideCarpet, @as(Tile.Sprite, '.'), Tile.Color{.red = 255, .green = 255, .blue = 255}});
    }
  }

  if (@rem(pos[0], 2) == 0 and @rem(pos[1], 2) == 0 and
    Tile.getStaticData(self.getTile(Coord{pos[0]-1, pos[1]})).?.walkable and
    Tile.getStaticData(self.getTile(Coord{pos[0]+1, pos[1]})).?.walkable and
    Tile.getStaticData(self.getTile(Coord{pos[0], pos[1]-1})).?.walkable and
    Tile.getStaticData(self.getTile(Coord{pos[0], pos[1]+1})).?.walkable)
  {
    mainspace.ecs.getComponentPtr(result, "tileType", Tile.Type).?.* = .CyanideCarpet;
    mainspace.ecs.getComponentPtr(result, "sprite", Tile.Sprite).?.* = '.';
  }

  if (self.inView(pos))
  {
    // If OutOfMemory, erase the oldest element
    self.tiles.put(pos, result) catch {
      //mainspace.ecs.removeEntity();self.tiles.values()[0].deinit();
      self.tiles.orderedRemoveAt(0);

      self.tiles.put(pos, result) catch unreachable;
    };
  }

  return result;
}

pub fn getTile(self: *Self, pos: Coord) ECS.Entity
{
  if (self.tiles.contains(pos))
  {
    return self.tiles.get(pos) orelse self.currentTile;
  } else
  {
    self.currentTile = self.generateTile(pos);
    return self.currentTile;
  }
}

/// Returns whether a world position is inside the viewing rectangle
pub fn inView(self: *Self, pos: Coord) bool
{
  return @reduce(.And, pos >= self.camPos) and @reduce(.And, pos < self.camPos+Coord{@intCast(ncurses.COLS), @intCast(ncurses.LINES)});
}

pub fn draw(self: *Self) void
{
  //_ = ncurses.mvaddnstr(1, 40, &std.fmt.bytesToHex(std.mem.toBytes(@as(u8, @intCast(this.camPos[0]))), .upper), 2);
  //_ = ncurses.mvaddnstr(1, 43, &std.fmt.bytesToHex(std.mem.toBytes(@as(u8, @intCast(this.camPos[1]))), .upper), 2);

  for (0..self.tiles.count(), self.tiles.iterator().keys, self.tiles.iterator().values) |i, pos, tile|
  {
    _ = i;

    if (self.inView(pos))
    {
      if (mainspace.ecs.getComponent(tile, "sprite", Tile.Sprite)) |sprite|
      {
        _ = ncurses.mvaddch(pos[1]-self.camPos[1], pos[0]-self.camPos[0], sprite);
      }
    }
  }

  for (self.objects) |object|
  {
    if (object) |id|
    {
      if (Object.getStaticData(id)) |data|
      {
        if (mainspace.ecs.getComponent(id, "pos", Coord)) |pos|
        {
          _ = ncurses.mvaddch(pos[1]-self.camPos[1], pos[0]-self.camPos[0], data.ch);
        }
      }
    } else
    {
      break;
    }
  }
}


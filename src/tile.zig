const Self = @This();

const std = @import("std");
const log = std.log;

const graphics = @import("graphics.zig");
const acs = graphics.acs;

const ECS = @import("ecs");
const Level = @import("scenes/level.zig");
const mainspace = @import("main.zig");
const nc = mainspace.nc;

pub const staticData = [_]struct
{
  walkable: bool,
  transparent: bool,
}{
  .{.walkable = true, .transparent = true},
  .{.walkable = false, .transparent = false},
  .{.walkable = false, .transparent = false},
};

pub const Type = enum(u8)
{
  CyanideCarpet,
  YellowWallpaper,
};

pub const Sprite = u8;

pub const Color = struct
{
  red: u8,
  green: u8,
  blue: u8,
};

pub fn getStaticData(tile: ECS.Entity.Unmanaged) ?@TypeOf(staticData[0])
{
  const tileType: Type =
    mainspace.ecs.getComponent(tile, "tileType", Type) orelse return null;

  return staticData[@intFromEnum(tileType)];
}

pub fn render(tiles: Level.Tilemap, pos: Level.Coord, camPos: Level.Coord)
  (error{TileNotFound} || graphics.Error)!void
{
  const tileType = mainspace.ecs.getComponent(
    tiles.get(pos) orelse return error.TileNotFound, "tileType", Type
  ).?;

  switch (tileType)
  {
    .YellowWallpaper => {
      const Neighbors = packed struct
      {
        up: bool,
        right: bool,
        down: bool,
        left: bool
      };

      const neighbors = Neighbors{
        .up =
          if (tiles.get(.{pos[0], pos[1]-1})) |neighbor|
            mainspace.ecs.getComponent(
              neighbor, "tileType", Type
            ).? == tileType
          else false,
        .right =
          if (tiles.get(.{pos[0]+1, pos[1]})) |neighbor|
            mainspace.ecs.getComponent(
              neighbor, "tileType", Type
            ).? == tileType
          else false,
        .down =
          if (tiles.get(.{pos[0], pos[1]+1})) |neighbor|
            mainspace.ecs.getComponent(
              neighbor, "tileType", Type
            ).? == tileType
          else false,
        .left =
          if (tiles.get(.{pos[0]-1, pos[1]})) |neighbor|
            mainspace.ecs.getComponent(
              neighbor, "tileType", Type
            ).? == tileType
          else false,
      };

      const ch: graphics.Char = switch (@as(u4, @bitCast(neighbors)))
      {
        @as(u4, @bitCast(Neighbors{
          .up = false, .right = false, .down = false, .left = false
        })) => '+',
        @as(u4, @bitCast(Neighbors{
          .up = false, .right = false, .down = false, .left = true
        })),
        @as(u4, @bitCast(Neighbors{
          .up = false, .right = true, .down = false, .left = false
        })),
        @as(u4, @bitCast(Neighbors{
          .up = false, .right = true, .down = false, .left = true
        })) => acs('q'),//nc.ACS_HLINE,
        @as(u4, @bitCast(Neighbors{
          .up = false, .right = false, .down = true, .left = false
        })),
        @as(u4, @bitCast(Neighbors{
          .up = true, .right = false, .down = false, .left = false
        })),
        @as(u4, @bitCast(Neighbors{
          .up = true, .right = false, .down = true, .left = false
        })) => acs('x'),//nc.ACS_VLINE,
        @as(u4, @bitCast(Neighbors{
          .up = true, .right = true, .down = false, .left = false
        })) => acs('m'),//nc.ACS_LLCORNER,
        @as(u4, @bitCast(Neighbors{
          .up = true, .right = false, .down = false, .left = true
        })) => acs('j'),//nc.ACS_LRCORNER,
        @as(u4, @bitCast(Neighbors{
          .up = false, .right = false, .down = true, .left = true
        })) => acs('k'),//nc.ACS_URCORNER,
        @as(u4, @bitCast(Neighbors{
          .up = false, .right = true, .down = true, .left = false
        })) => acs('l'),//nc.ACS_ULCORNER,
        @as(u4, @bitCast(Neighbors{
          .up = false, .right = true, .down = true, .left = true
        })) => acs('w'),//nc.ACS_TTEE,
        @as(u4, @bitCast(Neighbors{
          .up = true, .right = false, .down = true, .left = true
        })) => acs('u'),//nc.ACS_RTEE,
        @as(u4, @bitCast(Neighbors{
          .up = true, .right = true, .down = false, .left = true
        })) => acs('v'),//nc.ACS_BTEE,
        @as(u4, @bitCast(Neighbors{
          .up = true, .right = true, .down = true, .left = false
        })) => acs('t'),//nc.ACS_LTEE,
        @as(u4, @bitCast(Neighbors{
          .up = true, .right = true, .down = true, .left = true
        })) => acs('n'),//nc.ACS_PLUS,
      };

      try graphics.drawCh(pos - camPos, ch);
      //_ = nc.mvaddch(pos[1]-camPos[1], pos[0]-camPos[0], ch);
    },
    .CyanideCarpet => {
      try graphics.drawCh(pos - camPos, '.');
      //_ = nc.mvaddch(pos[1]-camPos[1], pos[0]-camPos[0], '.');
    },
  }
}

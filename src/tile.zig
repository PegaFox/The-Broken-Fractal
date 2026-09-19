const Self = @This();

const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;
const json = std.json;

const luaUtil = @import("lua.zig");
const Mod = @import("mod.zig");
const graphics = @import("graphics.zig");

const ECS = @import("ecs");
const Level = @import("scenes/level.zig");
const mainspace = @import("main.zig");

pub const StaticData = struct
{
  name: [:0]const u8,
  walkable: bool,
  color: graphics.Color,
  wallConnect: bool,
  /// If null, ch is determined by a lua function in the registry
  ch: ?u8,

  pub fn getCh(self: StaticData, tile: Self) u8
  {
    return self.ch orelse ch:{
      const state = Mod.luaEnv.?;

      const top = state.getTop();
      defer state.setTop(top);

      std.debug.assert(
        (state.getGlobal("fractal") catch unreachable) == .table
      );
      std.debug.assert(state.getField(-1, "mods") == .table);
      std.debug.assert(
        state.getField(-1, Mod.findTileMod(tile.type).name) == .table
      );
      std.debug.assert(state.getField(-1, "tiles") == .table);
      std.debug.assert(state.getField(-1, self.name) == .userdata);

      if (state.getField(-1, "ch") == .function)
      {
        luaUtil.luaTiles.luaTile.fromTile(state, tile);
        luaUtil.runFunction(state, .{.args = 1, .results = 1}) catch
          unreachable;
      }

      break:ch (state.toString(-1) catch unreachable)[0];
    };
  }
};
pub var staticData = std.ArrayList(StaticData).empty;

pub var nameTypes = std.HashMapUnmanaged(
  Mod.Identifier, Type, Mod.Identifier.HashContext, 80
).empty;

pub const Type = u16;
//pub const Type = enum(u8)
//{
//  CyanideCarpet,
//  YellowWallpaper,
//};

pub const Sprite = u8;

type: Type,
id: ECS.Entity.Unmanaged,

pub fn getStaticData(tile: Self) ?StaticData
{
  return staticData.items[tile.type];
}

pub fn draw(tiles: Level.Tilemap, pos: Level.Coord, camPos: Level.Coord)
  (error{TileNotFound} || graphics.Error)!void
{
  const tile = tiles.get(pos) orelse return error.TileNotFound;

  const data = getStaticData(tile).?;

  const ch: graphics.Char = if (!data.wallConnect) data.getCh(tile)
    else
    blk:{
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
            neighbor.type == tile.type
          else false,
        .right =
          if (tiles.get(.{pos[0]+1, pos[1]})) |neighbor|
            neighbor.type == tile.type
          else false,
        .down =
          if (tiles.get(.{pos[0], pos[1]+1})) |neighbor|
            neighbor.type == tile.type
          else false,
        .left =
          if (tiles.get(.{pos[0]-1, pos[1]})) |neighbor|
            neighbor.type == tile.type
          else false,
      };

      break:blk switch (@as(u4, @bitCast(neighbors)))
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
        })) => '\u{2500}',//nc.ACS_HLINE,
        @as(u4, @bitCast(Neighbors{
          .up = false, .right = false, .down = true, .left = false
        })),
        @as(u4, @bitCast(Neighbors{
          .up = true, .right = false, .down = false, .left = false
        })),
        @as(u4, @bitCast(Neighbors{
          .up = true, .right = false, .down = true, .left = false
        })) => '\u{2502}',//nc.ACS_VLINE,
        @as(u4, @bitCast(Neighbors{
          .up = true, .right = true, .down = false, .left = false
        })) => '\u{2514}',//nc.ACS_LLCORNER,
        @as(u4, @bitCast(Neighbors{
          .up = true, .right = false, .down = false, .left = true
        })) => '\u{2518}',//nc.ACS_LRCORNER,
        @as(u4, @bitCast(Neighbors{
          .up = false, .right = false, .down = true, .left = true
        })) => '\u{2510}',//nc.ACS_URCORNER,
        @as(u4, @bitCast(Neighbors{
          .up = false, .right = true, .down = true, .left = false
        })) => '\u{250C}',//nc.ACS_ULCORNER,
        @as(u4, @bitCast(Neighbors{
          .up = false, .right = true, .down = true, .left = true
        })) => '\u{252C}',//nc.ACS_TTEE,
        @as(u4, @bitCast(Neighbors{
          .up = true, .right = false, .down = true, .left = true
        })) => '\u{2524}',//nc.ACS_RTEE,
        @as(u4, @bitCast(Neighbors{
          .up = true, .right = true, .down = false, .left = true
        })) => '\u{2534}',//nc.ACS_BTEE,
        @as(u4, @bitCast(Neighbors{
          .up = true, .right = true, .down = true, .left = false
        })) => '\u{251C}',//nc.ACS_LTEE,
        @as(u4, @bitCast(Neighbors{
          .up = true, .right = true, .down = true, .left = true
        })) => '\u{253C}',//nc.ACS_PLUS,
      };
  };

  //try graphics.setDrawColor(data.color, @splat(0.0));
  try graphics.drawCh(pos - camPos, ch);
}

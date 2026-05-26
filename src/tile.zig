const Self = @This();

const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;
const json = std.json;

const Mod = @import("mod.zig");
const graphics = @import("graphics.zig");
const acs = graphics.acs;

const ECS = @import("ecs");
const Level = @import("scenes/level.zig");
const mainspace = @import("main.zig");

pub const StaticData = struct
{
  name: []const u8,
  walkable: bool,
  color: graphics.Color,
  wallConnect: bool,
  ch: u8,

  /// source is a *json.Scanner or a *json.Reader
  pub fn jsonParse(
    allocator: Allocator,
    source: anytype,
    options: json.ParseOptions,
  ) json.ParseError(@TypeOf(source.*))!@This()
  {
    var result: @This() = undefined;

    if (try source.next() != .object_begin) return error.UnexpectedToken;

    // Stall protection
    for (0..100) |_|
    {
      const token: ?json.Token = try source.nextAllocMax(
        allocator, .alloc_if_needed, options.max_value_len.?
      );//log.debug("Parsing token {}\n", .{token.?});
      const fieldNameHash = std.hash_map.hashString(switch (token.?) {
        inline .string, .allocated_string => |slice| slice,
        .object_end => { // No more fields.
          break;
        },
        else => {
          return error.UnexpectedToken;
        },
      });
      if (token.? == .allocated_string)
      {
        allocator.free(token.?.allocated_string);
      }
      
      switch (fieldNameHash)
      {
        std.hash_map.hashString("name") => result.name =
          try json.innerParse([]const u8, allocator, source, options),
        std.hash_map.hashString("walkable") => result.walkable =
          try json.innerParse(bool, allocator, source, options),
        std.hash_map.hashString("color") => {
          const colorRGB = try json.innerParse(
            struct {r: f32, g: f32, b: f32}, allocator, source, options
          );
          result.color = .{colorRGB.r, colorRGB.g, colorRGB.b};
        },
        std.hash_map.hashString("wallConnect") => result.wallConnect =
          try json.innerParse(bool, allocator, source, options),
        std.hash_map.hashString("ch") => {
          const chStr =
            try json.innerParse([]const u8, allocator, source, options);
          result.ch = if (chStr.len > 0) chStr[0] else ' ';
        },
        else => 
          if (options.ignore_unknown_fields) {
            try source.skipValue();
          } else {
            return error.UnknownField;
          }
      }
    }

    return result;
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

pub fn getStaticData(tile: ECS.Entity.Unmanaged) ?@TypeOf(staticData.items[0])
{
  const tileType: Type =
    mainspace.ecs.getComponent(tile, "tileType", Type) orelse return null;

  return staticData.items[tileType];
}

pub fn render(tiles: Level.Tilemap, pos: Level.Coord, camPos: Level.Coord)
  (error{TileNotFound} || graphics.Error)!void
{
  const tile = tiles.get(pos) orelse return error.TileNotFound;

  const tileType = mainspace.ecs.getComponent(
    tile, "tileType", Type
  ).?;
  const data = getStaticData(tile).?;

  const ch: graphics.Char = if (!data.wallConnect) data.ch
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
  };

  //try graphics.setDrawColor(data.color, @splat(0.0));
  try graphics.drawCh(pos - camPos, ch);
}

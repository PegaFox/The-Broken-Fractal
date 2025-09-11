const Self = @This();

const std = @import("std");
const log = std.log;

const ECS = @import("ecs");
const MarkedYellowWallpaper = @import("marked_yellow_wallpaper.zig").MarkedYellowWallpaper;
const mainspace = @import("main.zig");

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
  MarkedYellowWallpaper,
};

pub const Sprite = u8;

pub const Color = struct
{
  red: u8,
  green: u8,
  blue: u8,
};

pub fn getStaticData(tile: ECS.Entity) ?@TypeOf(staticData[0])
{
  const tileType: Type = mainspace.ecs.getComponent(tile, "tileType", Type) orelse return null;

  return staticData[@intFromEnum(tileType)];
}

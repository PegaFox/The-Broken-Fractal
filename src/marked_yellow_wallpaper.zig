const World = @import("world.zig");
const Tile = @import("tile.zig").Tile;

pub const MarkedYellowWallpaper = extern struct 
{
  parent: Tile = .{.type = .MarkedYellowWallpaper, .ch = '~', .red = 0xFF, .green = 0xFF, .blue = 0x00},

  markings: [64]u8,

  pub fn update(this: *Tile, playerPos: @Vector(2, i16)) void
  {
    _ = this;
    _ = playerPos;
  }
};

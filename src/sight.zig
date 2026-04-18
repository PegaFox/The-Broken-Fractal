//! For entities that can receive visual input, requires a 'pos' component

const Self = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const ViewMap = std.AutoHashMap(Level.Coord, void);

const ECS = @import("ecs");
const Tile = @import("tile.zig");
const TileMemory = @import("tile_memory.zig");
const Level = @import("scenes/level.zig");
const mainspace = @import("main.zig");

radius: u16,
view: ViewMap,

//pub fn init(allocator: Allocator, radius: u16) Self
//{
//  return .{
//    .radius = radius,
//    .view = .init(allocator),
//  };
//}
//
//pub fn deinit(self: *Self) void
//{
//  self.view.deinit();
//}

pub fn getView(self: *Self, parent: ECS.Entity.Unmanaged, level: *Level)
  error{MissingComponent, OutOfMemory}!void
{
  self.view.clearRetainingCapacity();

  const parentMemory =
    mainspace.ecs.getComponentPtr(parent, "tileMemory", TileMemory);

  const parentPos =
    mainspace.ecs.getComponent(parent, "pos", Level.Coord) orelse
      return error.MissingComponent;

  for (0..128) |r|
  {
    const ang = @as(f32, @floatFromInt(r))/128.0 * std.math.pi*2;

    const rayDir = @Vector(2, f32){@sin(ang), -@cos(ang)};
    var dis: f32 = 0;
    var rayPos: @Vector(2, f32) = @floatFromInt(parentPos);
    for (0..self.radius) |_|
    {
      const tile = try level.getTile(@intFromFloat(@round(rayPos)));

      try self.view.put(@intFromFloat(@round(rayPos)), undefined);
      if (parentMemory) |memory|
      {
        try memory.tiles.put(
          level.allocator, @intFromFloat(@round(rayPos)), tile
        );
      }

      if (mainspace.ecs.getComponent(
        tile, "tileType", Tile.Type).? == .YellowWallpaper)
      {
        break;
      }

      rayPos += rayDir;
      dis += 1;
    }
  }
}

pub fn inView(self: Self, pos: Level.Coord) bool
{
  return self.view.contains(pos);
}

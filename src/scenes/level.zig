const Self = @This();

const Scene = @import("../scene.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayHashMap = std.AutoArrayHashMap;
const log = std.log;

const ECS = @import("ecs");
const Player = @import("../player.zig");
const mainspace = @import("../main.zig");
const nc = mainspace.nc;

pub const Coord = @Vector(2, i16);

pub const Tilemap: type = ArrayHashMap(Coord, ECS.Entity.Unmanaged);

pub const VTable = struct
{
  generateTile: *const fn (self: *Self, pos: Coord)
    Allocator.Error!ECS.Entity.Unmanaged,
  getCamPos: *const fn (self: Self) Coord,
};

const maxObjects = 16;

tiles: Tilemap,

objects: [maxObjects]ECS.Entity.Unmanaged = undefined,
objectCount: std.math.IntFittingRange(0, maxObjects) = 0,

vtable: VTable,

scene: Scene,

/// Initialises common values (eg. self.tiles)
pub fn init(
  allocator: Allocator,
  vtable: Self.VTable,
  sceneVTable: Scene.VTable) Self
{
  return .{
    .tiles = .init(allocator),
    .vtable = vtable,
    .scene = .{
      .id = .Level,
      .vtable = sceneVTable
    },
  };
}

pub fn generateTile(self: *Self, pos: Coord)
  Allocator.Error!ECS.Entity.Unmanaged
{
  return try self.vtable.generateTile(self, pos);
}

pub fn getCamPos(self: Self) Coord
{
  return self.vtable.getCamPos(self);
}

pub fn getTile(self: *Self, pos: Coord) Allocator.Error!ECS.Entity.Unmanaged
{
  if (self.tiles.contains(pos))
  {
    return self.tiles.get(pos).?;
  } else
  {
    return try self.generateTile(pos);
  }
}

/// Returns whether a level position is inside the viewing rectangle
pub fn inView(self: *Self, pos: Coord) bool
{
  const camPos = self.getCamPos();

  return
    @reduce(.And, pos >= camPos) and
    @reduce(.And,
      pos < camPos+Coord{@intCast(nc.COLS), @intCast(nc.LINES)}
    );
}

/// Deinitialises common values (eg. self.tiles)
pub fn deinit(self: *Self) void
{
  self.tiles.deinit();

  self.* = undefined;
}

const Self = @This();

const Scene = @import("../scene.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log;
const graphics = @import("../graphics.zig");

const Object = @import("../object.zig");
const ECS = @import("ecs");
const Player = @import("../player.zig");
const mainspace = @import("../main.zig");
const sdl = mainspace.sdl;

pub const Coord = @Vector(2, i16);

pub const ID = enum
{
  Level0,
  Level1,
};

pub const Tilemap: type = std.array_hash_map.Auto(Coord, ECS.Entity.Unmanaged);

pub const VTable = struct
{
  generateTile: *const fn (self: *Self, pos: Coord)
    Allocator.Error!ECS.Entity.Unmanaged,
  getCamPos: *const fn (self: Self) Coord,
};

//const maxObjects = 16;
pub var objects = std.ArrayList(Object).empty;

id: ID,

allocator: Allocator,

tiles: Tilemap = .empty,

//objects: [maxObjects]ECS.Entity.Unmanaged = undefined,
//objectCount: std.math.IntFittingRange(0, maxObjects) = 0,

vtable: VTable,

scene: Scene,

pub var currentLevel: *const Self = undefined;
pub var levels = std.EnumArray(ID, *const Self).init(.{
  .Level0 = &@import("../levels/level_0.zig").level,
  .Level1 = &@import("../levels/level_1.zig").level,
});

pub const interface = Scene{
  .id = .Level,

  .vtable = .{
    // Init should not be called through here
    .init = struct {fn init(allocator: Allocator) !*const Scene
    {
      _ = allocator;
      return &interface;
    }}.init,

    .enter = struct {fn enter(self: *const Scene) !*const Scene
    {
      _ = self;

      return currentLevel.scene.enter();
    }}.enter,

    .getInput = struct {fn getInput(
      self: *const Scene,
      inputEvent: sdl.SDL_Event) !void
    {
      _ = self;
      
      try currentLevel.scene.getInput(inputEvent);
    }}.getInput,

    .update = struct {fn update(self: *const Scene) !void
    {
      _ = self;

      try currentLevel.scene.update();
    }}.update,

    .draw = struct {fn draw(self: *const Scene) !void
    {
      _ = self;

      try currentLevel.scene.draw();
    }}.draw,

    .exit = struct {fn exit(self: *const Scene) !void
    {
      _ = self;

      try currentLevel.scene.exit();
    }}.exit,

    // Deinit should not be called through here
    .deinit = struct {fn deinit(self: *const Scene) !void
    {
      _ = self;
    }}.deinit,
  }
};

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

/// Gets the position to center the camera on the specified entity (must have a pos component)
/// Used for getCamPos
pub fn getCenterCameraOn(entity: ECS.Entity.Unmanaged)
  error{MissingComponent}!Coord
{
  const pos = mainspace.ecs.get(entity, "pos", Coord) orelse
    return error.MissingComponent;

  return getCenterCamera(pos);
}

/// Gets the position to center the camera on the specified world coord
/// Used for getCamPos
pub fn getCenterCamera(pos: Coord) Coord
{
  return pos - graphics.size()/@as(Coord, @splat(2));
}

/// Returns whether a level position is inside the viewing rectangle
pub fn inView(self: *Self, pos: Coord) bool
{
  const camPos = self.getCamPos();

  return
    @reduce(.And, pos >= camPos) and
    @reduce(.And,
      pos < camPos+graphics.size()
    );
}

/// Deinitialises common values (eg. self.tiles)
pub fn deinit(self: *Self) void
{
  self.tiles.deinit(self.allocator);

  self.tiles = .empty;
}

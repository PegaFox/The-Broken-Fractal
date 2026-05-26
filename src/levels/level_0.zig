const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const ECS = @import("ecs");

const graphics = @import("../graphics.zig");
const mod = @import("../mod.zig");
const tile = @import("../tile.zig");
const Object = @import("../object.zig");
const Player = @import("../player.zig");
const Sight = @import("../sight.zig");
const TileMemory = @import("../tile_memory.zig");
const Scene = @import("../scene.zig");
const Level = @import("../scenes/level.zig");

const mainspace = @import("../main.zig");
const nc = mainspace.nc;
const sdl = mainspace.sdl;

// Remove extra tiles after this if possible
const maxTiles = 400;

pub var level: Level = .{
  .id = .Level0,
  .allocator = undefined,
  .scene = .{.id = .Level, .vtable = sceneVTable},
  .vtable = vtable,
};

const sceneVTable = Scene.VTable{
  .init = struct {fn init(allocator: Allocator) !*const Scene
  {
    level.allocator = allocator;

    return &level.scene;
  }}.init,

  .enter = struct {fn enter(self: *const Scene) !*const Scene
  {
    _ = self;
    return &level.scene;
  }}.enter,

  .getInput = struct {fn getInput(
    self: *const Scene,
    inputEvent: sdl.SDL_Event) !void
  {
    _ = self;
    _ = inputEvent;
  }}.getInput,

  .update = struct {fn update(self: *const Scene) !void {
    _ = self;

    const playerSight =
      mainspace.ecs.getPtr(Level.objects.items[0].id, "sight", Sight).?;
    var keys = level.tiles.keys();
    for (keys) |key|
    {
      if (level.tiles.count() <= maxTiles)
      {
        break;
      }

      if (!playerSight.inView(key))
      {
        log.debug("Remove tile {}\n", .{
          key - mainspace.ecs.getComponent(
            Level.objects.items[0].id, "pos", Level.Coord
          ).?
        });
        if (!level.tiles.orderedRemove(key)) unreachable;
        keys = level.tiles.keys();
      }
    }
  }}.update,

  .draw = struct {fn draw(self: *const Scene)
    (error{TileNotFound} || graphics.Error)!void
  {
    _ = self;
  }}.draw,

  .exit = struct {fn exit(self: *const Scene) !void {_ = self;}}.exit,

  .deinit = struct {fn deinit(self: *const Scene) !void
  {
    _ = self;
    level.deinit();
  }}.deinit,
};

const vtable = Level.VTable{
  .generateTile = struct {fn generateTile(self: *Level, pos: Level.Coord)
    Allocator.Error!ECS.Entity.Unmanaged
  {
    _ = self;
    _ = pos;

    //if (result == 0)
    //{
    //  result = mainspace.ecs.addEntity(.{
    //    .tileType = tile.nameTypes.get(
    //      .{.mod = "base", .name = "cyanideCarpet"}
    //    ).?,
    //  }).id;
    //}

    //if (@mod(pos[0], 2) == 1 and @mod(pos[1], 2) == 1)
    //{
    //  result = mainspace.ecs.addEntity(.{
    //    .tileType = tile.nameTypes.get(
    //      .{.mod = "base", .name = "cyanideCarpet"}
    //    ).?,
    //  }).id;
    //} else if (@mod(pos[0], 2) == 0 and @mod(pos[1], 2) == 0)
    //{
    //  result = mainspace.ecs.addEntity(.{
    //    .tileType = tile.nameTypes.get(
    //      .{.mod = "base", .name = "yellowWallpaper"}
    //    ).?,
    //  }).id;
    //} else
    //{
    //  if (mainspace.rand.uintLessThan(u2, 3) == 0)
    //  {
    //    result = mainspace.ecs.addEntity(.{
    //      .tileType = tile.nameTypes.get(
    //        .{.mod = "base", .name = "yellowWallpaper"}
    //      ).?,
    //    }).id;
    //  } else
    //  {
    //    result = mainspace.ecs.addEntity(.{
    //      .tileType = tile.nameTypes.get(
    //        .{.mod = "base", .name = "cyanideCarpet"}
    //      ).?,
    //    }).id;
    //  }
    //}

    //if (@rem(pos[0], 2) == 0 and @rem(pos[1], 2) == 0 and
    //  tile.getStaticData(
    //    try self.getTile(Level.Coord{pos[0]-1, pos[1]})
    //  ).?.walkable and
    //  tile.getStaticData(
    //    try self.getTile(Level.Coord{pos[0]+1, pos[1]})
    //  ).?.walkable and
    //  tile.getStaticData(
    //    try self.getTile(Level.Coord{pos[0], pos[1]-1})
    //  ).?.walkable and
    //  tile.getStaticData(
    //    try self.getTile(Level.Coord{pos[0], pos[1]+1})
    //  ).?.walkable)
    //{
    //  mainspace.ecs.getComponentPtr(result, "tileType", tile.Type).?.* =
    //    tile.nameTypes.get(
    //      .{.mod = "base", .name = "cyanideCarpet"}
    //    ).?;
    //}

    //return result;
    return 0;
  }}.generateTile,

  .getCamPos = struct {fn getCamPos(self: Level) Level.Coord
  {_ = self;
    return Level.getCenterCameraOn(Level.objects.items[0].id) catch unreachable;
  }}.getCamPos,
};

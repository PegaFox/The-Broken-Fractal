const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;

const ECS = @import("ecs");

const graphics = @import("../graphics.zig");
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
  .tiles = undefined,
  .objects = undefined,
  .scene = .{.id = .Level, .vtable = sceneVTable},
  .vtable = vtable,
};

const sceneVTable = Scene.VTable{
  .init = struct {fn init(allocator: Allocator) !*const Scene
  {
    level = .init(allocator, vtable, sceneVTable);

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
    const parent: *Level = @fieldParentPtr("scene", @constCast(self));

    if (inputEvent.type == sdl.SDL_EVENT_KEY_DOWN)
    {
      switch (inputEvent.key.key)
      {
        sdl.SDLK_H, sdl.SDLK_LEFT => try Player.move(parent, .{-1, 0}),
        sdl.SDLK_Y, sdl.SDLK_HOME => try Player.move(parent, .{-1, -1}),
        sdl.SDLK_J, sdl.SDLK_DOWN => try Player.move(parent, .{0, 1}),
        sdl.SDLK_B, sdl.SDLK_END => try Player.move(parent, .{-1, 1}),
        sdl.SDLK_K, sdl.SDLK_UP => try Player.move(parent, .{0, -1}),
        sdl.SDLK_U, sdl.SDLK_PAGEUP => try Player.move(parent, .{1, -1}),
        sdl.SDLK_L, sdl.SDLK_RIGHT => try Player.move(parent, .{1, 0}),
        sdl.SDLK_N, sdl.SDLK_PAGEDOWN => try Player.move(parent, .{1, 1}),
        sdl.SDLK_W, =>
          if (inputEvent.key.mod & sdl.SDL_KMOD_SHIFT != 0)
            try Player.write(parent),
        else => {},
      }
    }
  }}.getInput,

  .update = struct {fn update(self: *const Scene) !void {_ = self;}}.update,

  .draw = struct {fn draw(self: *const Scene) graphics.Error!void
  {
    const parent: *Level = @fieldParentPtr("scene", @constCast(self));

    //_ = nc.mvaddnstr(1, 40, &std.fmt.bytesToHex(std.mem.toBytes(@as(u8, @intCast(this.camPos[0]))), .upper), 2);
    //_ = nc.mvaddnstr(1, 43, &std.fmt.bytesToHex(std.mem.toBytes(@as(u8, @intCast(this.camPos[1]))), .upper), 2);
    const camPos = parent.getCamPos();

    const playerSight =
      mainspace.ecs.getComponentPtr(parent.objects[0], "sight", Sight).?;
    playerSight.getView(parent.objects[0], parent) catch unreachable;

    const playerMemory = mainspace.ecs.getComponentPtr(
      parent.objects[0], "tileMemory", TileMemory
    ).?;

    _ = nc.init_color(nc.COLOR_RED, 250, 250, 250);
    _ = nc.init_pair(1, nc.COLOR_RED, nc.COLOR_BLACK);

    for (playerMemory.tiles.keys()) |pos|
    {
      if (level.inView(pos))
      {
        if (mainspace.ecs.getComponent(
          parent.objects[0], "sight", Sight).?.inView(pos))
        {
          _ = nc.attroff(nc.COLOR_PAIR(1));
          _ = nc.attron(nc.COLOR_PAIR(0));
        } else
        {
          _ = nc.attroff(nc.COLOR_PAIR(0));
          _ = nc.attron(nc.COLOR_PAIR(1));
        }

        tile.render(playerMemory.tiles, pos, camPos) catch unreachable;
        
        //if (mainspace.ecs.getComponent(tile, "sprite", tile.Sprite)) |sprite|
        //{
        //  _ = nc.mvaddch(
        //    pos[1]-self.camPos[1], pos[0]-self.camPos[0], sprite
        //  );
        //}
      }
    }

    _ = nc.attroff(nc.COLOR_PAIR(1));
    _ = nc.attron(nc.COLOR_PAIR(0));

    for (parent.objects) |object|
    {
      if (Object.getStaticData(object)) |data|
      {
        if (mainspace.ecs.getComponent(object, "pos", Level.Coord)) |pos|
        {
          try graphics.drawCh(pos - camPos, data.ch);
          //_ = nc.mvaddch(
          //  pos[1]-camPos[1], pos[0]-camPos[0], data.ch
          //);
        }
      }
    }

    var keys = parent.tiles.keys();
    for (keys) |key|
    {
      if (parent.tiles.count() <= maxTiles)
      {
        break;
      }

      if (!playerSight.inView(key))
      {
        log.debug("Remove tile {}\n", .{
          key - mainspace.ecs.getComponent(
            parent.objects[0], "pos", Level.Coord
          ).?
        });
        if (!parent.tiles.orderedRemove(key)) unreachable;
        keys = parent.tiles.keys();
      }
    }
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
    var result: ECS.Entity.Unmanaged = undefined;
    if (@abs(@rem(pos[0], 2)) == 1 and @abs(@rem(pos[1], 2)) == 1)
    {
      result = mainspace.ecs.addEntityUnmanaged(.{
        .tileType = tile.Type.CyanideCarpet,
      });
    } else if (@rem(pos[0], 2) == 0 and @rem(pos[1], 2) == 0)
    {
      result = mainspace.ecs.addEntityUnmanaged(.{
        .tileType = tile.Type.YellowWallpaper,
      });
    } else
    {
      if (mainspace.rand.uintLessThan(u2, 3) == 0)
      {
        result = mainspace.ecs.addEntityUnmanaged(.{
          .tileType = tile.Type.YellowWallpaper,
        });
      } else
      {
        result = mainspace.ecs.addEntityUnmanaged(.{
          .tileType = tile.Type.CyanideCarpet,
        });
      }
    }

    if (@rem(pos[0], 2) == 0 and @rem(pos[1], 2) == 0 and
      tile.getStaticData(
        try self.getTile(Level.Coord{pos[0]-1, pos[1]})
      ).?.walkable and
      tile.getStaticData(
        try self.getTile(Level.Coord{pos[0]+1, pos[1]})
      ).?.walkable and
      tile.getStaticData(
        try self.getTile(Level.Coord{pos[0], pos[1]-1})
      ).?.walkable and
      tile.getStaticData(
        try self.getTile(Level.Coord{pos[0], pos[1]+1})
      ).?.walkable)
    {
      mainspace.ecs.getComponentPtr(result, "tileType", tile.Type).?.* =
        .CyanideCarpet;
    }

    try self.tiles.put(pos, result);

    return result;
  }}.generateTile,

  .getCamPos = struct {fn getCamPos(self: Level) Level.Coord
  {
    const playerPos =
      mainspace.ecs.getComponent(self.objects[0], "pos", Level.Coord).?;

    return playerPos - graphics.size()/@as(Level.Coord, @splat(2));
  }}.getCamPos,
};

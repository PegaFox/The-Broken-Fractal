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

pub var level: Level = .{
  .id = .Level1,
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
        sdl.SDLK_T => Level.currentLevel = Level.levels.get(.Level0),
        else => {},
      }
    }
  }}.getInput,

  .update = struct {fn update(self: *const Scene) !void {_ = self;}}.update,

  .draw = struct {fn draw(self: *const Scene)
    (error{TileNotFound} || graphics.Error)!void
  {
    const parent: *Level = @fieldParentPtr("scene", @constCast(self));

    //_ = nc.mvaddnstr(1, 40, &std.fmt.bytesToHex(std.mem.toBytes(@as(u8, @intCast(this.camPos[0]))), .upper), 2);
    //_ = nc.mvaddnstr(1, 43, &std.fmt.bytesToHex(std.mem.toBytes(@as(u8, @intCast(this.camPos[1]))), .upper), 2);
    const camPos = parent.getCamPos();

    const playerSight =
      mainspace.ecs.getPtr(Level.objects.items[0].id, "sight", Sight).?;
    playerSight.getView(Level.objects.items[0].id, parent) catch unreachable;

    const playerMemory = mainspace.ecs.getPtr(
      Level.objects.items[0].id, "tileMemory", TileMemory
    ).?;

    //_ = nc.init_color(1, 1000, 1000, 1000);
    //_ = nc.init_color(2, 0, 0, 0);
    //_ = nc.init_color(3, 250, 250, 250);
    //_ = nc.init_pair(1, 1, 2);
    //_ = nc.init_pair(2, 3, 2);

    for (playerMemory.tiles.keys()) |pos|
    {
      if (level.inView(pos))
      {
        if (mainspace.ecs.getComponent(
          Level.objects.items[0].id, "sight", Sight).?.inView(pos))
        {
          try graphics.setDrawColor(@splat(1.0), @splat(0.0));
          //_ = nc.attroff(nc.COLOR_PAIR(2));
          //_ = nc.attrset(nc.COLOR_PAIR(1));
        } else
        {
          try graphics.setDrawColor(@splat(0.25), @splat(0.0));
          //_ = nc.attroff(nc.COLOR_PAIR(1));
          //_ = nc.attrset(nc.COLOR_PAIR(2));
        }

        try tile.render(playerMemory.tiles, pos, camPos);
        
        //if (mainspace.ecs.getComponent(tile, "sprite", tile.Sprite)) |sprite|
        //{
        //  _ = nc.mvaddch(
        //    pos[1]-self.camPos[1], pos[0]-self.camPos[0], sprite
        //  );
        //}
      }
    }

    try graphics.setDrawColor(@splat(1.0), @splat(0.0));
    //_ = nc.attroff(nc.COLOR_PAIR(2));
    //_ = nc.attrset(nc.COLOR_PAIR(1));

    for (Level.objects.items) |object|
    {
      if (Object.getStaticData(object)) |data|
      {
        if (mainspace.ecs.getComponent(object.id, "pos", Level.Coord)) |pos|
        {
          try graphics.drawCh(pos - camPos, data.ch);
          //_ = nc.mvaddch(
          //  pos[1]-camPos[1], pos[0]-camPos[0], data.ch
          //);
        }
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
    if (@mod(pos[0], 6) < 2 and @mod(pos[1], 6) < 2)
    {
      result = mainspace.ecs.addEntity(.{
        .tileType = tile.nameTypes.get(
          .{.mod = "base", .name = "yellowWallpaper"}
        ).?,
      }).id;
    } else
    {
      result = mainspace.ecs.addEntity(.{
        .tileType = tile.nameTypes.get(
          .{.mod = "base", .name = "cyanideCarpet"}
        ).?,
      }).id;
    }

    try self.tiles.put(self.allocator, pos, result);

    return result;
  }}.generateTile,

  .getCamPos = struct {fn getCamPos(self: Level) Level.Coord
  {_ = self;
    return Level.getCenterCameraOn(Level.objects.items[0].id) catch unreachable;
  }}.getCamPos,
};

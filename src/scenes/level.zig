const Self = @This();

const Scene = @import("../scene.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log;
const graphics = @import("../graphics.zig");

const Mod = @import("../mod.zig");
const luaUtil = @import("../lua.zig");
const Turn = @import("../turn.zig");
const Tile = @import("../tile.zig");
const Object = @import("../object.zig");
const ECS = @import("ecs");
const Sight = @import("../sight.zig");
const TileMemory = @import("../tile_memory.zig");
const Player = @import("../player.zig");
const mainspace = @import("../main.zig");
const sdl = @import("sdl");

pub const Coord = @Vector(2, i16);

pub const ID = std.math.IntFittingRange(0, 999);//enum
//{
//  Level0,
//  Level1,
//};

pub const Tilemap: type = std.array_hash_map.Auto(Coord, Tile);

pub var gpa: Allocator = undefined;

//const maxObjects = 16;
pub var objects = std.ArrayList(Object).empty;

pub var sightToDraw = std.ArrayList(ECS.Entity.Unmanaged).empty;
pub var memoryToDraw = std.ArrayList(ECS.Entity.Unmanaged).empty;

//id: ID,
name: [:0]const u8,

camPos: Coord,
/// Directly accessing this should be avoided if possible. Try getTile(pos) instead
tiles: Tilemap = .empty,

//objects: [maxObjects]ECS.Entity.Unmanaged = undefined,
//objectCount: std.math.IntFittingRange(0, maxObjects) = 0,

//vtable: VTable,

//scene: Scene,

pub var currentLevel: ID = undefined;
pub var levels = std.ArrayList(Self).empty;

pub var nameIDs = std.HashMapUnmanaged(
  Mod.Identifier, ID, Mod.Identifier.HashContext, 80
).empty;
pub const interface = Scene{
  .id = .Level,

  .vtable = .{
    // This initializes global data common to all levels and should only be run once
    .init = struct {fn init(allocator: Allocator) !*const Scene
    {
      gpa = allocator;

      if (Mod.luaEnv) |lua|
      luaFail:{
        const top = lua.getTop();
        defer lua.setTop(top);

        if (lua.getGlobal("fractal") catch break:luaFail != .table)
          break:luaFail;
        if (!lua.getSubtable(-1, "mods")) break:luaFail;

        for (0.., Mod.mods.items) |m, mod|
        {
          _ = lua.pushString(mod.name);
          if (lua.getTable(-2) != .table) break:luaFail;
          if (!lua.getSubtable(-1, "levels")) break:luaFail;

          const levelStopID = if (m < Mod.mods.items.len-1)
            Mod.mods.items[m+1].levelStartID
          else
            levels.items.len;
          for (levels.items[mod.levelStartID..levelStopID]) |level|
          {
            _ = lua.pushString(level.name);
            if (lua.getTable(-2) != .table) break:luaFail;
            if (lua.getField(-1, "init") != .function) break:luaFail;
            // Push 'this' argument
            lua.pushNil();
            lua.copy(-3, -1);
            luaUtil.runFunction(lua, .{.args = 1, .results = 0}) catch
              break:luaFail;
          }
        }
      }

      return &interface;
    }}.init,

    .enter = struct {fn enter(self: *const Scene) !*const Scene
    {

      return self;
    }}.enter,

    .getInput = struct {fn getInput(
      self: *const Scene,
      inputEvent: sdl.SDL_Event) !void
    {
      _ = self;
      
      const level: *Self = &levels.items[currentLevel];

      if (inputEvent.type == sdl.SDL_EVENT_KEY_DOWN)
      {
        switch (inputEvent.key.key)
        {
          sdl.SDLK_H, sdl.SDLK_LEFT =>
            try Turn.push(gpa, &mainspace.ecs, objects.items[0]),
          sdl.SDLK_Y, sdl.SDLK_HOME => try Player.move(level, .{-1, -1}),
          sdl.SDLK_J, sdl.SDLK_DOWN => try Player.move(level, .{0, 1}),
          sdl.SDLK_B, sdl.SDLK_END => try Player.move(level, .{-1, 1}),
          sdl.SDLK_K, sdl.SDLK_UP => try Player.move(level, .{0, -1}),
          sdl.SDLK_U, sdl.SDLK_PAGEUP => try Player.move(level, .{1, -1}),
          sdl.SDLK_L, sdl.SDLK_RIGHT => try Player.move(level, .{1, 0}),
          sdl.SDLK_N, sdl.SDLK_PAGEDOWN => try Player.move(level, .{1, 1}),
          //sdl.SDLK_W, =>
          //  if (inputEvent.key.mod & sdl.SDL_KMOD_SHIFT != 0)
          //    try Player.write(level),
          sdl.SDLK_T =>
            currentLevel =
              @mod(currentLevel+1, @as(ID, @truncate(levels.items.len))),
          //sdl.SDLK_H, sdl.SDLK_LEFT => try Player.move(level, .{-1, 0}),
          //sdl.SDLK_Y, sdl.SDLK_HOME => try Player.move(level, .{-1, -1}),
          //sdl.SDLK_J, sdl.SDLK_DOWN => try Player.move(level, .{0, 1}),
          //sdl.SDLK_B, sdl.SDLK_END => try Player.move(level, .{-1, 1}),
          //sdl.SDLK_K, sdl.SDLK_UP => try Player.move(level, .{0, -1}),
          //sdl.SDLK_U, sdl.SDLK_PAGEUP => try Player.move(level, .{1, -1}),
          //sdl.SDLK_L, sdl.SDLK_RIGHT => try Player.move(level, .{1, 0}),
          //sdl.SDLK_N, sdl.SDLK_PAGEDOWN => try Player.move(level, .{1, 1}),
          //sdl.SDLK_W, =>
          //  if (inputEvent.key.mod & sdl.SDL_KMOD_SHIFT != 0)
          //    try Player.write(level),
          //sdl.SDLK_T =>
          //  currentLevel =
          //    @mod(currentLevel+1, @as(ID, @truncate(levels.items.len))),
          else => {},
        }
      }
    }}.getInput,

    .update = struct {fn update(self: *const Scene) !void
    {_ = self;
      var luaSuccess = false;
      if (Mod.luaEnv) |lua|
      luaFail:{

        const top = lua.getTop();
        defer lua.setTop(top);

        if (lua.getGlobal("fractal") catch break:luaFail != .table)
          break:luaFail;
        if (!lua.getSubtable(-1, "mods")) break:luaFail;
        _ = lua.pushString(Mod.findLevelMod(currentLevel).name);
        if (lua.getTable(-2) != .table) break:luaFail;
        if (!lua.getSubtable(-1, "levels")) break:luaFail;
        _ = lua.pushString(levels.items[currentLevel].name);
        if (lua.getTable(-2) != .table) break:luaFail;
        if (lua.getField(-1, "update") != .function) break:luaFail;
        // Push 'this' argument
        lua.pushNil();
        lua.copy(-3, -1);
        luaUtil.runFunction(lua, .{.args = 1, .results = 0}) catch
          break:luaFail;

        luaSuccess = true;
      }

      // Default update functionality
      if (!luaSuccess)
      {
        _ = luaUtil.luaCamera.centerOnInner(
          .{.parent = .{.handle = currentLevel}},
          .{.id = objects.items[0].id}
        ) catch unreachable;
      }

    }}.update,

    .draw = struct {fn draw(self: *const Scene) !void
    {
      _ = self;

      const level: *Self = &levels.items[currentLevel];

      //_ = nc.mvaddnstr(1, 40, &std.fmt.bytesToHex(std.mem.toBytes(@as(u8, @intCast(this.camPos[0]))), .upper), 2);
      //_ = nc.mvaddnstr(1, 43, &std.fmt.bytesToHex(std.mem.toBytes(@as(u8, @intCast(this.camPos[1]))), .upper), 2);

      for (sightToDraw.items) |entity|
      {
        const sight =
          mainspace.ecs.getPtr(entity, "sight", Sight).?;
        sight.getView(entity, level) catch unreachable;
      }
      sightToDraw.clearRetainingCapacity();

      for (memoryToDraw.items) |entity|
      {
        const memory = mainspace.ecs.getPtr(
          entity, "tileMemory", TileMemory
        ).?;
        //log.debug("Memory size: {}\n", .{memory.tiles.count()});

        for (memory.tiles.keys()) |pos|
        {
          if (level.inView(pos))
          {
            if (mainspace.ecs.getComponent(
              entity, "sight", Sight).?.inView(pos))
            {
              try graphics.setDrawColor(@splat(1.0), @splat(0.0));
            } else
            {
              try graphics.setDrawColor(@splat(0.25), @splat(0.0));
            }

            try Tile.draw(memory.tiles, pos, level.camPos);
          }
        }
      }
      memoryToDraw.clearRetainingCapacity();

      try graphics.setDrawColor(@splat(1.0), @splat(0.0));

      for (objects.items) |object|
      {
        if (Object.getStaticData(object)) |data|
        {
          if (mainspace.ecs.getComponent(object.id, "pos", Object.Pos)) |pos|
          {
            try graphics.drawCh(pos.pos - level.camPos, data.ch);
          }
        } else |_| unreachable;
      }
    }}.draw,

    .exit = struct {fn exit(self: *const Scene) !void
    {
      _ = self;
    }}.exit,

    // This deinitializes global data common to all levels and should only be run once
    .deinit = struct {fn deinit(self: *const Scene) !void
    {
      _ = self;

      objects.deinit(gpa);
    }}.deinit,
  }
};

pub fn generateTile(self: *Self, pos: Coord)
  Allocator.Error!Tile
{
  var result: Tile = .{.type = 0, .id = 0};

  if (Mod.luaEnv) |lua|
  luaFail:{
    const top = lua.getTop();
    defer lua.setTop(top);

    if (lua.getGlobal("fractal") catch break:luaFail != .table)
      break:luaFail;
    if (!lua.getSubtable(-1, "mods")) break:luaFail;
    _ = lua.pushString(Mod.findLevelMod(currentLevel).name);
    if (lua.getTable(-2) != .table) break:luaFail;
    if (!lua.getSubtable(-1, "levels")) break:luaFail;
    _ = lua.pushString(levels.items[currentLevel].name);
    if (lua.getTable(-2) != .table) break:luaFail;
    if (lua.getField(-1, "generateTile") != .function) break:luaFail;
    // Push 'this' argument
    lua.pushNil();
    lua.copy(-3, -1);
    lua.pushAny(pos) catch break:luaFail;
    luaUtil.runFunction(lua, .{.args = 2, .results = 1}) catch break:luaFail;

    if (!lua.isTable(-1)) break:luaFail;

    result = .{
      .type = Tile.nameTypes.get(
        switch (lua.lenRaiseErr(-1))
        {
          1 => id:{
            if (lua.getIndex(-1, 1) != .string) break:luaFail;

            break:id .{
              .mod = "base",
              .name = lua.toString(-1) catch unreachable
            };
          },
          2 => id:{
            if (lua.getIndex(-1, 1) != .string) break:luaFail;
            if (lua.getIndex(-2, 2) != .string) break:luaFail;

            break:id .{
              .mod = lua.toString(-2) catch unreachable,
              .name = lua.toString(-1) catch unreachable
            };
          },
          else => break:luaFail
        }
      ) orelse break:luaFail,

      .id = mainspace.ecs.addEntity(.{}).id
    };
  }

  // If lua function failed, generate default tile
  if (result.id == 0)
  {
    result = .{
      .type = @as(Tile.Type, 0),
      .id = mainspace.ecs.addEntity(.{}).id
    };
  }

  try self.tiles.put(gpa, pos, result);

  return result;
}

//pub fn getCamPos(self: Self) Coord
//{
//  _ = self;
//  return getCenterCameraOn(objects.items[0].id) catch unreachable;
//}

pub fn getTile(self: *Self, pos: Coord) Allocator.Error!Tile
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
  _ = self;

  const level: *Self = &levels.items[currentLevel];

  return
    @reduce(.And, pos >= level.camPos) and
    @reduce(.And,
      pos < level.camPos+graphics.size()
    );
}

/// Deinitialises common values (eg. self.tiles)
pub fn deinit(self: *Self) void
{
  self.tiles.deinit(gpa);
  self.tiles = .empty;
}

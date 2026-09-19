const Self = @This();

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const json = std.json;
const log = std.log;

const lua = @import("zlua");
const input = @import("input.zig");
const graphics = @import("graphics.zig");
const luaUtil = @import("lua.zig");
const Mod = @import("mod.zig");
const Turn = @import("turn.zig");
const Level = @import("scenes/level.zig");
const ECS = @import("ecs");
const mainspace = @import("main.zig");

pub const StaticData = struct
{
  name: [:0]const u8,
  ch: u8,
  color: graphics.Color,

  volume: ?f32,
  mass: ?f32,

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
        std.hash_map.hashString("color") => {
          const colorRGB = try json.innerParse(
            struct {r: f32, g: f32, b: f32}, allocator, source, options
          );
          result.color = .{colorRGB.r, colorRGB.g, colorRGB.b};
        },
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

pub const Pos = struct
{
  pos: Level.Coord,
  
  /// For multiple objects stacked on one tile
  next: ECS.Entity.Unmanaged,
};

type: Type,
id: ECS.Entity.Unmanaged,

pub fn init(objectType: Type, pos: Level.Coord, components: anytype) Self
{
  const result = Self{
    .id = mainspace.ecs.addEntity(components).id,
    .node = .{.next = null},
  };

  mainspace.ecs.addC(result.id, "objectType", objectType);
  mainspace.ecs.addC(result.id, "pos", pos);

  return result;
}

pub fn getStaticData(object: Self) error{InvalidID}!StaticData
{
  if (object.type > staticData.items.len) return error.InvalidID;
  return staticData.items[object.type];
}

/// If thread is not null, resumes from where it left off. Otherwise getAction will create a new thread for this object
/// If this returns yielded, the lua function was suspended to wait for engine resources. In this case, the yielded function is contained in thread
pub fn getAction(object: Self, ecs: *ECS, thread: ?luaUtil.PausedThread)
  error{LuaFail, NoTurnFunction}!
  union(enum) {Done: Turn, Yield: luaUtil.PausedThread}
{
  const state = Mod.luaEnv orelse return error.LuaFail;
  //errdefer if (thread == null) state.pop(1);

  if (input.currentInput == null)
  {
    input.currentInput = input.getInput();
  }

  const endTop = state.getTop();
  defer state.setTop(endTop);

  if (thread == null)
  {
    const top = state.getTop();
    errdefer state.setTop(top);

    if ((state.getGlobal("fractal") catch return error.LuaFail) != .table)
      return error.LuaFail;
    if (!state.getSubtable(-1, "mods")) return error.LuaFail;
    _ = state.pushString(Mod.findObjectMod(object.type).name);
    if (state.getTable(-2) != .table) return error.LuaFail;
    if (!state.getSubtable(-1, "objects")) return error.LuaFail;
    if (state.getField(-1, staticData.items[object.type].name) != .table)
    {
      return error.NoTurnFunction;
    }
    if (state.getField(-1, "takeTurn") != .function)
    {
      return error.NoTurnFunction;
    }
    state.rotate(top+1, 1);
    state.setTop(top+1);
  
    // Push 'this' argument
    luaUtil.luaObject.generateLua(state, ecs, object);
  }

  if (
    luaUtil.runCoroutine(state, thread, if (thread == null) 1 else 0) catch
      return error.LuaFail) |outThread|
  {
    return .{.Yield = outThread};
  }

  if (state.typeOf(-1) != .table) return error.LuaFail;

  std.debug.assert(state.getField(lua.registry_index, "fractal") == .table);
  std.debug.assert(state.getField(-1, "actions") == .table);
  state.pushValue(-3);
  state.setIndex(-2, object.id);

  if (state.getField(-3, "cost") != .number) return error.LuaFail;

  return .{.Done = .{
    .object = object,
    .startTime = Turn.present,
    .cost = @intCast(state.toInteger(-1) catch unreachable),
  }};
}

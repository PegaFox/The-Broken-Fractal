const Self = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const json = std.json;
const log = std.log;

const lua = @import("zlua");
const graphics = @import("graphics.zig");
const luaUtil = @import("lua.zig");
const Mod = @import("mod.zig");
const Turn = @import("turn.zig");
const Level = @import("scenes/level.zig");
const ECS = @import("ecs");
const mainspace = @import("main.zig");

pub const StaticData = struct
{
  name: []const u8,
  ch: u8,
  color: graphics.Color,

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

id: ECS.Entity.Unmanaged,
/// For multiple objects stacked on one tile
node: std.SinglyLinkedList.Node = .{},

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

pub fn getStaticData(object: Self) error{NoID, InvalidID}!StaticData
{
  const objectType: Type =
    mainspace.ecs.get(object.id, "objectType", Type) orelse return error.NoID;

  if (objectType > staticData.items.len) return error.InvalidID;
  return staticData.items[objectType];
}

pub fn getAction(object: Self, ecs: *ECS) Turn
{
  const objectType =
    ecs.get(object.id, "objectType", Type) orelse
      return .{
        .object = object,
        .startTime = Turn.present,
        .cost = 1,
      };

  if (Mod.luaEnv) |state|
  luaFail:{
    const top = state.getTop();
    defer state.setTop(top);

    if (state.getGlobal("fractal") catch break:luaFail != .table)
      break:luaFail;
    if (!state.getSubtable(-1, "mods")) break:luaFail;
    _ = state.pushString(Mod.findObjectMod(objectType).name);
    if (state.getTable(-2) != .table) break:luaFail;
    if (!state.getSubtable(-1, "objects")) break:luaFail;
    _ = state.pushString(staticData.items[objectType].name);
    if (state.getTable(-2) != .table) break:luaFail;
    if (state.getField(-1, "takeTurn") != .function) break:luaFail;
    // Push 'this' argument
    luaUtil.luaObject.generateLua(state, ecs, object);
    luaUtil.runFunction(state, .{.args = 1, .results = 1}) catch
      break:luaFail;
    if (state.typeOf(-1) != .table) break:luaFail;

    std.debug.assert(state.getField(lua.registry_index, "fractal") == .table);
    std.debug.assert(state.getField(-1, "actions") == .table);
    state.pushValue(-3);
    state.setIndex(-2, object.id);

    if (state.getField(-3, "cost") != .number) break:luaFail;

    return .{
      .object = object,
      .startTime = Turn.present,
      .cost = @intCast(state.toInteger(-1) catch unreachable),
    };
  }

  return .{
    .object = object,
    .startTime = Turn.present,
    .cost = 1,
  };
}

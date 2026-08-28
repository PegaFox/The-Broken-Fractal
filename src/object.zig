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

var currentInput: ?[]const u8 = null;
/// io parameter is used for getting inputs
pub fn getAction(object: Self, ecs: *ECS) error{NoInput, LuaFail}!Turn
{
  const state = Mod.luaEnv orelse return error.LuaFail;

  const top = state.getTop();
  defer state.setTop(top);

  if ((state.getGlobal("fractal") catch return error.LuaFail) != .table)
    return error.LuaFail;
  if (!state.getSubtable(-1, "mods")) return error.LuaFail;
  _ = state.pushString(Mod.findObjectMod(object.type).name);
  if (state.getTable(-2) != .table) return error.LuaFail;
  if (!state.getSubtable(-1, "objects")) return error.LuaFail;
  _ = state.pushString(staticData.items[object.type].name);
  if (state.getTable(-2) != .table) return error.LuaFail;
  if (state.getField(-1, "takeTurn") != .function) return error.LuaFail;

  // Checks if the function has a parameter for input
  const needsInput =
  blk:{
    state.pushValue(-1);
    var functionInfo: lua.DebugInfo = undefined;
    state.getInfo(.{.@">" = true, .u = true}, &functionInfo);

    break:blk functionInfo.num_params == 2;
  };
  
  // Push 'this' argument
  luaUtil.luaObject.generateLua(state, ecs, object);
  if (needsInput)
  {
    if (currentInput == null)
    {
      currentInput = (input.getInput() catch unreachable) orelse
        return error.NoInput;
    }

    state.createTable(0, 1);
    state.pushFunction(luaUtil.toApiFunction("inputIs", struct {
      fn inputIs(@"test": []const u8) bool
      {
        if (currentInput != null and std.mem.eql(u8, @"test", currentInput.?))
        {
          currentInput = null;

          return true;
        } else
        {
          return false;
        }
      }
    }.inputIs, .{}));
    state.setField(-2, "is");
  }

  luaUtil.runFunction(state, .{
    .args = if (needsInput) 2 else 1,
    .results = 1
  }) catch
    return error.LuaFail;
  if (state.typeOf(-1) != .table) return error.LuaFail;

  std.debug.assert(state.getField(lua.registry_index, "fractal") == .table);
  std.debug.assert(state.getField(-1, "actions") == .table);
  state.pushValue(-3);
  state.setIndex(-2, object.id);

  if (state.getField(-3, "cost") != .number) return error.LuaFail;

  return .{
    .object = object,
    .startTime = Turn.present,
    .cost = @intCast(state.toInteger(-1) catch unreachable),
  };
}

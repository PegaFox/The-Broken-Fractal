//! Manages object action scheduling and time
const Self = @This();

const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;

const lua = @import("zlua");
const luaUtil = @import("lua.zig");
const Mod = @import("mod.zig");
const ECS = @import("ecs");
const tile = @import("tile.zig");
const Object = @import("object.zig");
const Level = @import("scenes/level.zig");

const mainspace = @import("main.zig");

pub const Timestamp = u16;
pub const Duration = Timestamp;

pub var present: Timestamp = 0;

/// Action information is stored in the lua registry at fractal.actions[object.id]
object: Object,
startTime: Timestamp,
cost: Duration,

pub fn endTime(self: Self) Timestamp
{
  return self.startTime + self.cost;
}

pub var queue: std.PriorityQueue(
  Self,
  void,
  struct {fn compare(_: void, a: Self, b: Self) std.math.Order
  {
    // TODO: Ensure we never compare two actions from different objects as equal
    return std.math.order(
      a.endTime(),
      b.endTime()
    );
  }}.compare
) = .empty;

/// Pushes the object's action to the action queue
pub fn push(allocator: Allocator, ecs: *ECS, object: Object) !void
{
  try queue.push(allocator, object.getAction(ecs));
}

var stepTimePendingTurn: Self =
  .{.object = .{.id = 0}, .startTime = 0, .cost = 0};
/// Steps time forward until the next event
/// Returns how much time passed
pub fn stepTime(ecs: *ECS) Duration
{// First get input, then get output, storing the retrieved turn for the next input
  //const luaState = Mod.luaEnv.?;
  //const hasAction = turn.getLuaAction(luaState);

  //// TODO: Add error handling here
  //if (hasAction)
  //{
  //  luaUtil.runFunction(luaState) catch unreachable;
  //}

  const turn = stepTimePendingTurn.object.getAction(ecs);
  queue.update(stepTimePendingTurn, turn) catch {};

  stepTimePendingTurn = queue.peek() orelse return 0;

  const luaState = Mod.luaEnv.?;
  const hasAction = stepTimePendingTurn.getLuaAction(luaState);

  // This needs to be calculated because we don't know how long the action has been in progress
  const duration = stepTimePendingTurn.endTime() - present;

  // TODO: Add error handling here
  if (hasAction)
  {
    luaUtil.runFunction(luaState) catch unreachable;
  }

  present += duration;
  return duration;
}

/// Performs the next event
pub fn doEvent() void
{
  const turn = queue.peek() orelse return;

  const luaState = Mod.luaEnv.?;
  const hasAction = turn.getLuaAction(luaState);

  //// This needs to be calculated because we don't know how long the action has been in progress
  //const duration = turn.endTime() - present;

  // TODO: Add error handling here
  if (hasAction)
  {
    luaUtil.runFunction(luaState) catch unreachable;
  }

  //queue.update(turn, turn.object.getAction(ecs)) catch unreachable;
}

/// Pushes the associated action's make function onto the lua stack
/// Returns true if a lua action was found
pub fn getLuaAction(self: Self, state: *lua.Lua) bool
{
  var top = state.getTop();
  defer state.setTop(top);

  std.debug.assert(state.getField(lua.registry_index, "fractal") == .table);
  std.debug.assert(state.getField(-1, "actions") == .table);
  if (state.getIndex(-1, self.object.id) != .table) return false;
  if (state.getField(-1, "make") != .function) return false;

  // Remove intermediate stack values, leaving the make function
  top += 1;
  state.rotate(-4, 1);
  
  return true;
}

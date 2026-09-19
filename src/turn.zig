//! Manages object action scheduling and time
const Self = @This();

const std = @import("std");
const log = std.log;
const Io = std.Io;
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
/// If the action cannot be pushed (eg. user input is required for the action), then a temporary junk action is pushed until something else can be used
pub fn push(allocator: Allocator, ecs: *ECS, object: Object) !void
{_ = ecs;
  try queue.push(
    allocator,
    //object.getAction(ecs) catch
      .{.object = object, .startTime = present, .cost = 0}
  );
}

/// This is used to keep track of partially completed object turns waiting for input
var stepTimePendingAction: ?luaUtil.PausedThread = null;
/// Steps time forward until the next event
/// Returns how much time passed
pub fn stepTime(ecs: *ECS) Duration
{
  if (queue.items.len == 0)
  {
    return 0;
  }

  const currentTurn = queue.peek().?;

  // This needs to be calculated because we don't know how long the action has been in progress
  const duration = currentTurn.endTime() - present;
  present += duration;

  const luaState = Mod.luaEnv.?;
  const hasAction = currentTurn.getLuaAction(luaState);

  // TODO: Add error handling here
  if (hasAction)
  {
    //log.debug("imafinnagonna\n", .{});
    //luaUtil.dumpStack(luaState);
    luaUtil.runFunction(luaState, .{}) catch unreachable;
  }

  var newTurn: Self = undefined;
  switch (
    currentTurn.object.getAction(ecs, stepTimePendingAction) catch |e|
      switch (e)
    {
      error.LuaFail =>
      {
        stepTimePendingAction = null;
        //if (@errorReturnTrace()) |trace| {std.debug.dumpErrorReturnTrace(trace);}
        return 0;
      },
      error.NoTurnFunction =>
      {
        _ = queue.pop();
        return 0;
      }
    })
  {
    .Done => |turn|
    {
      stepTimePendingAction = null;
      newTurn = turn;
    },
    .Yield => |thread|
    {
      stepTimePendingAction = thread;
      return 0;
    },
  }
  queue.update(currentTurn, newTurn) catch {};

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

const Self = @This();

const std = @import("std");

const Value = union(enum)
{
  value: u32,
  pointer: *u32,
};

/// Current state of the overtime stat
value: Value,
/// Rate of change each timestep
delta: i16,

/// Quickly access the associated value without the need to handle union fields
pub fn valuePtr(self: *Self) *u32
{
  return
    if (self.value == .value) &self.value.value
    else if (self.value == .pointer) self.value.pointer
    else unreachable;
}

pub fn update(self: *Self) void
{
  const value = self.valuePtr();

  value.* = @max(0, @as(i33, value.*) + self.delta);
}

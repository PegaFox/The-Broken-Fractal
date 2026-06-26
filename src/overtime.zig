const Self = @This();

const std = @import("std");

const Value = union(enum)
{
  value: u32,
  pointer: *u32,
};

value: Value,
moveRate: i16,

pub fn update(self: *Self) void
{
  const value = if (self.value == .value)
    &self.value.value
  else if (self.value == .pointer)
    self.value.pointer
  else unreachable;

  value.* = @max(0, @as(i33, value.*) + self.moveRate);
}

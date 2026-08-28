const Self = @This();

const std = @import("std");

const graphics = @import("graphics.zig");

const Object = @import("object.zig");

/// Max volume the inventory can hold
capacity: f32,

items: std.ArrayList(Object),

pub fn draw(self: Self) graphics.Error!void
{
  var drawY: u16 = 0;

  for (self.items.items) |object|
  {
    try graphics.drawStr(
      .{0, @intCast(drawY)},
      (object.getStaticData() catch unreachable).name
    );

    drawY += 1;
  }
}

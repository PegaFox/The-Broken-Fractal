const Self = @This();

const std = @import("std");

pub var world = @import("world.zig").init();
pub var writing = @import("writing.zig").init();

enter: *const fn (self: *Self) *Self,

getInput: *const fn (self: *Self, inputEvent: c_int) void,

update: *const fn (self: *Self) void,

draw: *const fn (self: *Self) void,

exit: *const fn (self: *Self) void,

deinit: *const fn (self: *Self) void,

const Self = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const mainspace = @import("main.zig");
const sdl = mainspace.sdl;

pub const ID = enum
{
  Level,
  Writing,
};

pub var scenes = std.EnumArray(ID, *const Self).init(.{
  .Level = &@import("scenes/level.zig").interface,
  .Writing = &@import("scenes/writing.zig").scene,
});

pub var currentScene: *const Self = undefined;

pub const VTable = struct
{
  init: *const fn (allocator: Allocator) anyerror!*const Self,
  
  enter: *const fn (self: *const Self) anyerror!*const Self,
  
  getInput: *const fn (self: *const Self, inputEvent: sdl.SDL_Event)
    anyerror!void,
  
  update: *const fn (self: *const Self) anyerror!void,
  
  draw: *const fn (self: *const Self) anyerror!void,
  
  exit: *const fn (self: *const Self) anyerror!void,
  
  deinit: *const fn (self: *const Self) anyerror!void,
};

id: ID,

vtable: VTable,

pub fn init(self: *const Self, allocator: Allocator) anyerror!*const Self
{
  return try self.vtable.init(allocator);
}
  
pub fn enter(self: *const Self) anyerror!*const Self
{
  return try self.vtable.enter(self);
}
  
pub fn getInput(self: *const Self, inputEvent: sdl.SDL_Event) anyerror!void
{
  try self.vtable.getInput(self, inputEvent);
}
  
pub fn update(self: *const Self) anyerror!void
{
  try self.vtable.update(self);
}
 
pub fn draw(self: *const Self) anyerror!void
{
  try self.vtable.draw(self);
}
  
pub fn exit(self: *const Self) anyerror!void
{
  try self.vtable.exit(self);
}
  
pub fn deinit(self: *const Self) anyerror!void
{
  try self.vtable.deinit(self);
}

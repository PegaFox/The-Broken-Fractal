const Self = @import("scene.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log;

const Player = @import("../player.zig");
const ncurses = @cImport({@cInclude("ncurses.h");});
const mainspace = @import("../main.zig");

pub fn init() Self
{
  return .{
    .enter = struct {fn enter(self: *Self) *Self {
      return self;
    }}.enter,

    .getInput = struct {fn getInput(self: *Self, inputEvent: c_int) void
    {
      _ = self;

      switch (inputEvent)
      {
        'h', ncurses.KEY_LEFT => Player.move(&mainspace.world, .{-1, 0}),
        'y', ncurses.KEY_HOME => Player.move(&mainspace.world, .{-1, -1}),
        'j', ncurses.KEY_DOWN => Player.move(&mainspace.world, .{0, 1}),
        'b', ncurses.KEY_END => Player.move(&mainspace.world, .{-1, 1}),
        'k', ncurses.KEY_UP => Player.move(&mainspace.world, .{0, -1}),
        'u', ncurses.KEY_PPAGE => Player.move(&mainspace.world, .{1, -1}),
        'l', ncurses.KEY_RIGHT => Player.move(&mainspace.world, .{1, 0}),
        'n', ncurses.KEY_NPAGE => Player.move(&mainspace.world, .{1, 1}),
        'W', => Player.write(&mainspace.world),
        else => {},
      }

    }}.getInput,

    .update = struct {fn update(self: *Self) void {_ = self;}}.update,

    .draw = struct {fn draw(self: *Self) void
    {
      _ = self;

      _ = ncurses.erase();
   
      mainspace.world.draw();

      _ = ncurses.refresh();
    }}.draw,

    .exit = struct {fn exit(self: *Self) void {_ = self;}}.exit,

    .deinit = struct {fn deinit(self: *Self) void {_ = self;}}.deinit,
  };
}

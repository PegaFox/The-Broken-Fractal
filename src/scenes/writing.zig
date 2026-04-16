const Scene = @import("../scene.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log;

const ncurses = @cImport({@cInclude("ncurses.h");});
const mainspace = @import("../main.zig");

pub var writingBuffer: []u8 = undefined;
pub var bufferWidth: u8 = 0;
pub var cursorPos = @Vector(2, u8){0, 0};

pub const scene = Scene{
  .id = .Writing,

  .vtable = .{
    .init = struct {fn init(allocator: Allocator) !*const Scene
    {
      _ = allocator;
      return &scene;
    }}.init,

    .enter = struct {fn enter(self: *const Scene) !*const Scene {
      cursorPos = .{0, 0};

      return self;
    }}.enter,

    .getInput = struct {fn getInput(self: *const Scene, inputEvent: c_int) !void
    {
      _ = self;

      const size =
        @Vector(2, u8){bufferWidth, @intCast(writingBuffer.len/bufferWidth)};

      switch (inputEvent)
      {
        -1 => {},
        27, '\n' => {
          try Scene.currentScene.exit();
          Scene.currentScene = try Scene.scenes.get(.Level).enter();
        },
        ncurses.KEY_LEFT =>
          cursorPos +%= @as(@Vector(2, u8), @bitCast(@Vector(2, i8){-1, 0})),
        ncurses.KEY_HOME =>
          cursorPos +%= @as(@Vector(2, u8), @bitCast(@Vector(2, i8){-1, -1})),
        ncurses.KEY_DOWN =>
          cursorPos +%= @as(@Vector(2, u8), @bitCast(@Vector(2, i8){0, 1})),
        ncurses.KEY_END =>
          cursorPos +%= @as(@Vector(2, u8), @bitCast(@Vector(2, i8){-1, 1})),
        ncurses.KEY_UP =>
          cursorPos +%= @as(@Vector(2, u8), @bitCast(@Vector(2, i8){0, -1})),
        ncurses.KEY_PPAGE =>
          cursorPos +%= @as(@Vector(2, u8), @bitCast(@Vector(2, i8){1, -1})),
        ncurses.KEY_RIGHT =>
          cursorPos +%= @as(@Vector(2, u8), @bitCast(@Vector(2, i8){1, 0})),
        ncurses.KEY_NPAGE =>
          cursorPos +%= @as(@Vector(2, u8), @bitCast(@Vector(2, i8){1, 1})),
        ncurses.KEY_BACKSPACE => {
          cursorPos[0] =
            @mod(cursorPos[0]+%@as(u8, @bitCast(@as(i8, -1))), size[0]);
          writingBuffer[@intCast(cursorPos[1]*bufferWidth + cursorPos[0])] =
            ' ';
        },
        else => {
          writingBuffer[@intCast(cursorPos[1]*bufferWidth + cursorPos[0])] =
            @intCast(inputEvent & 0xFF);
          cursorPos[0] = @rem(cursorPos[0]+1, bufferWidth);
        },
      }

      cursorPos %= size;

    }}.getInput,

    .update = struct {fn update(self: *const Scene) !void {_ = self;}}.update,

    .draw = struct {fn draw(self: *const Scene) !void
    {
      _ = self;

      _ = ncurses.erase();

      _ = ncurses.mvaddstr(
        0, 1, "Writing mode. Use arrows to move and escape or enter to leave"
      );

      _ = ncurses.move(1, 1);
      for (0..bufferWidth) |x|
      {
        _ = x;
        _ = ncurses.addch('-');
      }

      for (0..writingBuffer.len/bufferWidth) |y|
      {
        _ = ncurses.mvaddch(@intCast(y+2), 0, '|');
        _ = ncurses.addnstr(writingBuffer.ptr + bufferWidth*y, bufferWidth);
        _ = ncurses.addch('|');
      }

      _ = ncurses.move(@intCast(writingBuffer.len/bufferWidth + 2), 1);
      for (0..bufferWidth) |x|
      {
        _ = x;
        _ = ncurses.addch('-');
      }

      _ = ncurses.mvaddch(cursorPos[1]+2, cursorPos[0]+1, '_');

      _ = ncurses.refresh();
    }}.draw,

    .exit = struct {fn exit(self: *const Scene) !void {_ = self;}}.exit,

    .deinit = struct {fn deinit(self: *const Scene) !void {_ = self;}}.deinit,
  }
};

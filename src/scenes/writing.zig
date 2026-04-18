const Scene = @import("../scene.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log;
const graphics = @import("../graphics.zig");

const mainspace = @import("../main.zig");
const nc = mainspace.nc;
const sdl = mainspace.sdl;

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

    .getInput = struct {fn getInput(
      self: *const Scene,
      inputEvent: sdl.SDL_Event) !void
    {
      _ = self;

      const size =
        @Vector(2, u8){bufferWidth, @intCast(writingBuffer.len/bufferWidth)};

      if (inputEvent.type == sdl.SDL_EVENT_KEY_DOWN)
      {
        switch (inputEvent.key.key)
        {
          sdl.SDLK_ESCAPE, sdl.SDLK_RETURN => { // SDLK_RETURN evaluates to a carriage return, I couldn't find a line feed key so I'm using this
            try Scene.currentScene.exit();
            Scene.currentScene = try Scene.scenes.get(.Level).enter();
          },
          sdl.SDLK_LEFT =>
            cursorPos +%= @as(@Vector(2, u8), @bitCast(@Vector(2, i8){-1, 0})),
          sdl.SDLK_HOME =>
            cursorPos +%= @as(@Vector(2, u8), @bitCast(@Vector(2, i8){-1, -1})),
          sdl.SDLK_DOWN =>
            cursorPos +%= @as(@Vector(2, u8), @bitCast(@Vector(2, i8){0, 1})),
          sdl.SDLK_END =>
            cursorPos +%= @as(@Vector(2, u8), @bitCast(@Vector(2, i8){-1, 1})),
          sdl.SDLK_UP =>
            cursorPos +%= @as(@Vector(2, u8), @bitCast(@Vector(2, i8){0, -1})),
          sdl.SDLK_PAGEUP =>
            cursorPos +%= @as(@Vector(2, u8), @bitCast(@Vector(2, i8){1, -1})),
          sdl.SDLK_RIGHT =>
            cursorPos +%= @as(@Vector(2, u8), @bitCast(@Vector(2, i8){1, 0})),
          sdl.SDLK_PAGEDOWN =>
            cursorPos +%= @as(@Vector(2, u8), @bitCast(@Vector(2, i8){1, 1})),
          sdl.SDLK_BACKSPACE => {
            cursorPos[0] =
              @mod(cursorPos[0]+%@as(u8, @bitCast(@as(i8, -1))), size[0]);
            writingBuffer[@intCast(cursorPos[1]*bufferWidth + cursorPos[0])] =
              ' ';
          },
          else => {
            writingBuffer[@intCast(cursorPos[1]*bufferWidth + cursorPos[0])] =
              @truncate(inputEvent.key.key);
            cursorPos[0] = @rem(cursorPos[0]+1, bufferWidth);
          },
        }
      }

      cursorPos %= size;

    }}.getInput,

    .update = struct {fn update(self: *const Scene) !void {_ = self;}}.update,

    .draw = struct {fn draw(self: *const Scene) !void
    {
      _ = self;

      try graphics.drawStr(
        .{1, 0}, "Writing mode. Use arrows to move and escape or enter to leave"
      );
      //_ = nc.mvaddstr(
      //  0, 1, "Writing mode. Use arrows to move and escape or enter to leave"
      //);

      //_ = nc.move(1, 1);
      for (0..bufferWidth) |x|
      {
        try graphics.drawCh(.{@intCast(x+1), 1}, '-');
        //_ = x;
        //_ = nc.addch('-');
      }

      for (0..writingBuffer.len/bufferWidth) |y|
      {
        try graphics.drawCh(.{0, @intCast(y+2)}, '|');
        try graphics.drawStr(
          .{1, @intCast(y+2)}, writingBuffer[bufferWidth*y..bufferWidth * (y+1)]
        );
        try graphics.drawCh(.{bufferWidth+2, @intCast(y+2)}, '|');
        //_ = nc.mvaddch(@intCast(y+2), 0, '|');
        //_ = nc.addnstr(writingBuffer.ptr + bufferWidth*y, bufferWidth);
        //_ = nc.addch('|');
      }

      //_ = nc.move(@intCast(writingBuffer.len/bufferWidth + 2), 1);
      for (0..bufferWidth) |x|
      {
        try graphics.drawCh(
          .{@intCast(x+1), @intCast(writingBuffer.len/bufferWidth + 2)}, '-'
        );
        //_ = x;
        //_ = nc.addch('-');
      }

      try graphics.drawCh(.{cursorPos[0]+1, cursorPos[1]+2}, '_');
      //_ = nc.mvaddch(cursorPos[1]+2, cursorPos[0]+1, '_');
    }}.draw,

    .exit = struct {fn exit(self: *const Scene) !void {_ = self;}}.exit,

    .deinit = struct {fn deinit(self: *const Scene) !void {_ = self;}}.deinit,
  }
};

const std = @import("std");
const log = std.log;

const graphics = @import("graphics.zig");

const Scene = @import("scene.zig");

const mainspace = @import("main.zig");
const nc = mainspace.nc;
const sdl = mainspace.sdl;

pub fn getInput() !void
{
  // Emergency loop breakout
  for (0..100) |_|
  {
    const event: sdl.SDL_Event = pollEvent() orelse break;

    switch (event.type)
    {
      sdl.SDL_EVENT_QUIT => mainspace.running = false,
      else => {},
    }

    try Scene.currentScene.getInput(event);
  }
}

fn pollEvent() ?sdl.SDL_Event
{
  var event: sdl.SDL_Event = undefined;

  if (graphics.sdlWindow != null)
  {
    // Conditional returns on success so we can fetch both events depending on window/terminal focus
    if (sdl.SDL_PollEvent(&event))
      return event;
  }

  if (graphics.ncurses)
  {
    const key: c_int = nc.getch();

    if (key == -1)
    {
      return null;
    }

    event = switch (key)
    {
      3, 26 => .{.quit = .{.type = sdl.SDL_EVENT_QUIT}},
      nc.KEY_RESIZE => .{.window = .{
        .type = sdl.SDL_EVENT_WINDOW_RESIZED, 
        .windowID = 0,
        .data1 = nc.COLS,
        .data2 = nc.LINES,
      }},
      31...nc.KEY_RESIZE-1, nc.KEY_RESIZE+1...nc.KEY_MAX => .{// 31 is the first visible ASCII character
        .key = .{
          .type = sdl.SDL_EVENT_KEY_DOWN,
          .windowID = 0,
          .which = 0,
          //.scancode = sdl.SDL_Keymod: SDL_Scancode = @import("std").mem.zeroes(SDL_Scancode), // I'm not sure how to convert keycodes to scancodes in sdl
          .key = std.ascii.toLower(@intCast(key)), // SDL_Keycode uses ascii representation for the first 128 chars (excluding uppercase letters which are handled by the mod field)
          .mod = @intCast(
            sdl.SDL_KMOD_LSHIFT *
            @intFromBool(std.ascii.isUpper(@intCast(key)))
          ),
          .raw = @intCast(key),
          .down = true,
          .repeat = false, // We don't know if it's a key repeat, but it doesn't matter much
        }
      },
      else => return null,
    };

    event.common.timestamp = mainspace.timer.read();

    return event;
  }

  return null;
}

const std = @import("std");
const log = std.log;

const Level = @import("scenes/level.zig");

const mainspace = @import("main.zig");
const nc = mainspace.nc;
const sdl = mainspace.sdl;

pub const Error = error{RenderFail};

/// Set to lowest common denominator at comptime
var monochrome = true;

pub var ncurses = false;
pub var sdlWindow: ?*sdl.SDL_Window = null;
var sdlRenderer: ?*sdl.SDL_Renderer = null;

pub const Char = u8;

/// Workaround for c-translate issue with ncurses
/// TODO: Try building ncurses with zig to see if that fixes this
const acsBit: Char = 0x80;
pub fn acs(ch: Char) Char
{
  return acsBit | ch;
}

/// Leaving arguments as null will use the highest quality renderer available
pub fn init(useTerminal: ?bool, useWindow: ?bool, useColors: ?bool) void
{
  if (useWindow == null or useWindow == true)
  initFail: {
    if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO))
    {
      log.info("SDL init failed: {s}\n", .{sdl.SDL_GetError()});
      break:initFail;
    }

    if (!sdl.SDL_CreateWindowAndRenderer(
      "The Broken Fractal", 800, 600, 0, &sdlWindow, &sdlRenderer))
    {
      log.info("SDL init failed: {s}\n", .{sdl.SDL_GetError()});
      break:initFail;
    }

    log.info("SDL initialized\n", .{});
  }

  if (useTerminal == null or useTerminal == true)
  {
    // Start ncurses
    var err: c_int = nc.OK;

    _ = nc.initscr() orelse {err = nc.ERR;};
    err |= nc.raw();
    err |= nc.nodelay(nc.stdscr, true);
    err |= nc.noecho();
    err |= nc.keypad(nc.stdscr, true);
    err |= nc.curs_set(0);

    if (useColors == null or useColors == true)
    {
      if (nc.can_change_color())
      {
        monochrome = false;

        err |= nc.start_color();
      } else
      {
        monochrome = true;
      }
    } else
    {
      monochrome = true;
    }

    if (err == nc.ERR)
    {
      log.info("Ncurses init failed\n", .{});
      ncurses = false;
    } else
    {
      log.info("Ncurses initialized\n", .{});
      ncurses = true;
    }
  }
}

pub fn deinit() void
{
  if (ncurses)
  {
    _ = nc.endwin();
    ncurses = false;
  }

  if (sdlWindow != null or sdlRenderer != null)
  {
    if (sdlWindow != null)
    {
      sdl.SDL_DestroyWindow(sdlWindow);
      sdlWindow = null;
    }
    if (sdlRenderer != null)
    {
      sdl.SDL_DestroyRenderer(sdlRenderer);
      sdlRenderer = null;
    }

    sdl.SDL_Quit();
  }
}

pub fn size() Level.Coord
{
  var minSize: Level.Coord =
    @splat(std.math.maxInt(@typeInfo(Level.Coord).vector.child));

  if (ncurses)
  {
    minSize = @min(minSize, Level.Coord{@intCast(nc.COLS), @intCast(nc.LINES)});
  }

  if (sdlWindow != null and sdlRenderer != null)
  {

  }

  return minSize;
}

pub fn startFrame() Error!void
{
  if (ncurses)
  {
    if (nc.clear() == nc.ERR) return Error.RenderFail;
  }

  if (sdlWindow != null and sdlRenderer != null)
  {
    if (!sdl.SDL_SetRenderDrawColorFloat(sdlRenderer, 0.0, 0.0, 0.0, 1.0))
      return Error.RenderFail;
    if (!sdl.SDL_RenderClear(sdlRenderer))
      return Error.RenderFail;
  }
}

pub fn endFrame() Error!void
{
  if (ncurses)
  {
    if (nc.refresh() == nc.ERR) return Error.RenderFail;
  }

  if (sdlWindow != null and sdlRenderer != null)
  {
    if (!sdl.SDL_RenderPresent(sdlRenderer))
      return Error.RenderFail;
  }
}

pub fn drawCh(pos: Level.Coord, ch: Char) Error!void
{
  if (ncurses)
  {
    var chSpr: nc.chtype = ch;
    if (chSpr & acsBit > 0)
    {
      chSpr = chSpr & ~acsBit | 0x400000;
    }

    if (nc.mvaddch(pos[1], pos[0], chSpr) == nc.ERR) return Error.RenderFail;
  }

  if (sdlWindow != null and sdlRenderer != null)
  {
    //if (!sdl.SDL_RenderPresent(sdlRenderer))
    //  return Error.RenderFail;
  }
}

pub fn drawStr(pos: Level.Coord, str: []const Char) Error!void
{
  if (ncurses)
  {
    if (nc.mvaddnstr(pos[1], pos[0], str.ptr, @intCast(str.len)) == nc.ERR)
      return Error.RenderFail;
  }

  if (sdlWindow != null and sdlRenderer != null)
  {
    //if (!sdl.SDL_RenderPresent(sdlRenderer))
    //  return Error.RenderFail;
  }
}

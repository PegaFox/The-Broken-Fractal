const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log;

const Level = @import("scenes/level.zig");

const mainspace = @import("main.zig");
const nc = mainspace.nc;
const sdl = mainspace.sdl;

pub const Error = error{RenderFail};

var gpa: Allocator = undefined;

/// Set to lowest common denominator at comptime
/// A value of zero means unlimited colors
var maxColors: u32 = 2;
var colors: ?[]const Color = &.{@splat(0), @splat(1)};

pub const NCursesData = struct {
  colors: std.HashMapUnmanaged(Color, @TypeOf(nc.COLOR_BLACK), struct
  {
    const Self = @This();
    const resolution = 1_000;
    const Res = std.math.IntFittingRange(0, resolution);

    fn normFloatToInt(float: f32) Res
    {
      return @trunc(float * resolution);
    }

    pub fn hash(self: Self, color: Color) u64
    {
      _ = self;

      std.debug.assert(@bitSizeOf(Res) * 3 <= @bitSizeOf(u64));

      return
        @as(u64, normFloatToInt(color[2])) << @bitSizeOf(Res)*2 |
        @as(u64, normFloatToInt(color[1])) << @bitSizeOf(Res) |
        normFloatToInt(color[0]);
    }

    pub fn eql(self: Self, color1: Color, color2: Color) bool
    {
      return self.hash(color1) == self.hash(color2);
    }
  }, 80),
  colorPairs: std.AutoHashMapUnmanaged(
    [2]@TypeOf(nc.COLOR_BLACK), @TypeOf(nc.COLOR_PAIRS)
  ),

  /// Gets the ncurses color index for the given color, cacheing it if the color is new
  pub fn getColor(self: *@This(), color: Color) Error!@TypeOf(nc.COLOR_BLACK)
  {
    if (!self.colors.contains(color))
    {
      const newIndex: c_short = @intCast(self.colors.count()+1);

      self.colors.put(gpa, color, newIndex) catch {};

      const colorInt: @Vector(3, c_short) =
        @trunc(color * @as(Color, @splat(1000.0)));
      log.debug("Init color {}) {} : {}\n", .{newIndex, color, colorInt});
      if (nc.init_color(
        newIndex, colorInt[0], colorInt[1], colorInt[2]) == nc.ERR
      ) return Error.RenderFail;

      return newIndex;
    }
    return self.colors.get(color).?;
  }
};
pub var ncData: ?NCursesData = null;

pub const SdlData = struct {
  window: *sdl.SDL_Window,
  renderer: *sdl.SDL_Renderer,
};
pub var sdlData: ?SdlData = null;

pub const Char = u8;

pub const Color = @Vector(3, f32);

/// Workaround for c-translate issue with ncurses
/// TODO: Try building ncurses with zig to see if that fixes this
const acsBit: Char = 0x80;
pub fn acs(ch: Char) Char
{
  return acsBit | ch;
}

/// Leaving arguments as null will use the highest quality renderer available
pub fn init(
  allocator: Allocator,
  useTerminal: ?bool,
  useWindow: ?bool,
  palette: ?[]const Color) (Error || Allocator.Error)!void
{
  gpa = allocator;

  if (useWindow == null or useWindow == true)
  initFail: {
    if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO))
    {
      log.info("SDL init failed: {s}\n", .{sdl.SDL_GetError()});
      break:initFail;
    }

    var window: ?*sdl.SDL_Window = null;
    var renderer: ?*sdl.SDL_Renderer = null;
    if (!sdl.SDL_CreateWindowAndRenderer(
      "The Broken Fractal", 800, 600, 0, &window, &renderer))
    {
      log.info("SDL init failed: {s}\n", .{sdl.SDL_GetError()});
      break:initFail;
    }

    sdlData = .{
      .window = window.?,
      .renderer = renderer.?,
    };

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

    if (nc.has_colors())
    {
      err |= nc.start_color();

      // If palette == null: use ncurses palette (if any)
      // else: use min of ncurses and palette
      if (nc.can_change_color() and palette != null)
      {
        maxColors = @min(palette.?.len, @max(0, nc.COLORS));

        colors = blk:{
          const mem = try allocator.alloc(Color, palette.?.len);
          @memcpy(mem, palette.?);
          break:blk mem;
        };
      } else
      {
        maxColors = @max(0, nc.COLORS);
        colors =
          if (nc.can_change_color())
            null
          else
            &.{
              .{0, 0, 0},
              .{1, 0, 0},
              .{0, 1, 0},
              .{1, 1, 0},
              .{0, 0, 1},
              .{1, 0, 1},
              .{0, 1, 1},
              .{1, 1, 1},
            };
      }
    } else
    {
      maxColors = 2;
      colors = &.{@splat(0), @splat(1)};
    }

    if (err == nc.ERR)
    {
      log.info("Ncurses init failed\n", .{});
      ncData = null;
    } else
    {
      log.info("Ncurses initialized\n", .{});
      ncData = .{
        .colors = .empty,
        .colorPairs = .empty,
      };
    }

    if (ncData != null and colors != null)
    {
      for (colors.?) |color|
      {
        _ = try ncData.?.getColor(color);
      }
    }
  }
}

pub fn deinit() void
{
  if (ncData != null)
  {
    log.debug("Colors:\n", .{});
    var it = ncData.?.colors.iterator();
    while (it.next()) |apiColor|
    {
      var ncColor: @Vector(3, c_short) = undefined;
      if (nc.color_content(
        @intCast(apiColor.value_ptr.*),
        &ncColor[0],
        &ncColor[1],
        &ncColor[2]) == nc.ERR)
      {
        log.debug(
          "COLOR {}: {} NOT FOUND\n",
          .{apiColor.value_ptr.*, apiColor.key_ptr.*});
      }

      log.debug(
        "{}) {}: {}\n",
        .{apiColor.value_ptr.*, apiColor.key_ptr.*, ncColor});
    }

    _ = nc.endwin();

    ncData.?.colorPairs.deinit(gpa);
    ncData.?.colors.deinit(gpa);
    ncData = null;
  }

  if (sdlData) |gfx|
  {
    sdl.SDL_DestroyWindow(gfx.window);
    sdl.SDL_DestroyRenderer(gfx.renderer);

    sdl.SDL_Quit();

    sdlData = null;
  }

  if (colors) |pal|
  {
    gpa.free(pal);
  }
}

pub fn size() Level.Coord
{
  var minSize: Level.Coord =
    @splat(std.math.maxInt(@typeInfo(Level.Coord).vector.child));

  if (ncData != null)
  {
    minSize = @min(minSize, Level.Coord{@intCast(nc.COLS), @intCast(nc.LINES)});
  }

  if (sdlData != null)
  {

  }

  return minSize;
}

pub fn startFrame() Error!void
{
  if (ncData) |*gfx|
  {_ = gfx;
    //gfx.colors.clearRetainingCapacity();
    //gfx.colorPairs.clearRetainingCapacity();

    if (nc.attrset(nc.COLOR_PAIR(0)) == nc.ERR) return Error.RenderFail;
    if (nc.clear() == nc.ERR) return Error.RenderFail;
  }

  if (sdlData) |gfx|
  {
    if (!sdl.SDL_SetRenderDrawColorFloat(gfx.renderer, 0.0, 0.0, 0.0, 1.0))
      return Error.RenderFail;
    if (!sdl.SDL_RenderClear(gfx.renderer))
      return Error.RenderFail;
  }
}

pub fn endFrame() Error!void
{
  if (ncData != null)
  {
    if (nc.refresh() == nc.ERR) return Error.RenderFail;
  }

  if (sdlData) |gfx|
  {
    if (!sdl.SDL_RenderPresent(gfx.renderer))
      return Error.RenderFail;
  }
}

pub fn setDrawColor(fg: Color, bg: Color) Error!void
{
  if (ncData) |*gfx|
  {
    if (nc.can_change_color())
    {
      const fgIndex = try gfx.getColor(fg);
      const bgIndex = try gfx.getColor(bg);

      var pairIndex: @TypeOf(nc.COLOR_PAIRS) = undefined;
      if (!gfx.colorPairs.contains(.{fgIndex, bgIndex}))
      {
        gfx.colorPairs.put(
          gpa, .{fgIndex, bgIndex}, @intCast(gfx.colorPairs.count()+1)
        ) catch {};

        if (nc.init_pair(
          @intCast(gfx.colorPairs.count()),
          @intCast(fgIndex),
          @intCast(bgIndex)) == nc.ERR
        ) return Error.RenderFail;
      }
      pairIndex = gfx.colorPairs.get(.{fgIndex, bgIndex}).?;

      //log.debug("fg[{}] = {}, bg[{}] = {}, pair = {}\n", .{fgIndex, fg, bgIndex, bg, pairIndex});
      if (nc.attrset(nc.COLOR_PAIR(pairIndex)) == nc.ERR)
        return Error.RenderFail;
    }
  }

  if (sdlData) |gfx|
  {_ = gfx;
    //if (!sdl.SDL_SetRenderDrawColorFloat(
    //  gfx.renderer, color[0], color[1], color[2], 1.0))
    //{
    //  return Error.RenderFail;
    //}
  }
}

pub fn drawCh(pos: Level.Coord, ch: Char) Error!void
{
  if (ncData != null)
  {
    var chSpr: nc.chtype = ch;
    if (chSpr & acsBit > 0)
    {
      chSpr = chSpr & ~acsBit | 0x400000;
    }

    if (nc.mvaddch(pos[1], pos[0], chSpr) == nc.ERR) return Error.RenderFail;
  }

  if (sdlData) |gfx|
  {_ = gfx;
    //if (!sdl.SDL_RenderPresent(sdlRenderer))
    //  return Error.RenderFail;
  }
}

pub fn drawStr(pos: Level.Coord, str: []const Char) Error!void
{
  if (ncData != null)
  {
    if (nc.mvaddnstr(pos[1], pos[0], str.ptr, @intCast(str.len)) == nc.ERR)
      return Error.RenderFail;
  }

  if (sdlData) |gfx|
  {_ = gfx;
    //if (!sdl.SDL_RenderPresent(sdlRenderer))
    //  return Error.RenderFail;
  }
}

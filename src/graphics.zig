const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log;

const Level = @import("scenes/level.zig");

const mainspace = @import("main.zig");
const c = @import("c");
const nc = @import("ncurses");
const sdl = @import("sdl");

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

  /// Gets the ncurses color index for the given color, caching it if the color is new
  pub fn getColor(self: *@This(), color: Color) Error!@TypeOf(nc.COLOR_BLACK)
  {
    if (!self.colors.contains(color))
    {
      const newIndex: c_short = @intCast(self.colors.count()+1);

      self.colors.put(gpa, color, newIndex) catch {};

      const colorInt: @Vector(3, c_short) =
        @trunc(color * @as(Color, @splat(1000.0)));
      log.debug("Init color {}) {}: {}\n", .{newIndex, color, colorInt});
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
  font: *sdl.TTF_Font,
  textEngine: *sdl.TTF_TextEngine,
  text: *sdl.TTF_Text,

  /// This sucks, but we need a uniform grid and even monospace fonts may be inconsistent for unicode characters
  glyphSize: Level.Coord,
  /// Number of characters visible in the window
  viewSize: Level.Coord,
};
pub var sdlData: ?SdlData = null;

/// A unicode codepoint
pub const Char = u21;

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
    
    if (!sdl.TTF_Init())
    {
      log.info("SDL_ttf init failed: {s}\n", .{sdl.SDL_GetError()});
      break:initFail;
    }

    var window: ?*sdl.SDL_Window = null;
    var renderer: ?*sdl.SDL_Renderer = null;
    if (!sdl.SDL_CreateWindowAndRenderer(
      "The Broken Fractal", 800, 600, 0, &window, &renderer))
    {
      log.info(
        "SDL window/renderer creation failed: {s}\n", .{sdl.SDL_GetError()});
      break:initFail;
    }

    const font = sdl.TTF_OpenFont("font.ttf", 30) orelse
    {
      log.info("SDL font init failed: {s}\n", .{sdl.SDL_GetError()});
      break:initFail;
    };
    if (!font.SetFontSize(600.0 / 32.0))
    {
      log.info("SDL font size update failed: {s}\n", .{sdl.SDL_GetError()});
      break:initFail;
    }

    const textEngine = sdl.TTF_CreateRendererTextEngine(renderer).?;
    const text: *sdl.TTF_Text = textEngine.CreateText(font, "", 0);

    const testGlyph: *sdl.SDL_Surface = sdl.TTF_RenderGlyph_Solid(
      font, 'H', .{.r = 255, .g = 255, .b = 255, .a = 255}
    ).?;
    defer testGlyph.DestroySurface();

    sdlData = .{
      .window = window.?,
      .renderer = renderer.?,
      .font = font,
      .textEngine = textEngine,
      .text = text,
      .glyphSize = .{@intCast(testGlyph.w), @intCast(testGlyph.h)},
      .viewSize = .{32, 32},
    };

    log.info("SDL initialized\n", .{});
  }

  if (useTerminal == null or useTerminal == true)
  {
    // Start ncurses
    var err: c_int = nc.OK;

    _ = c.setlocale(c.LC_ALL, "en_US.UTF-8");
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
    gfx.textEngine.DestroyRendererTextEngine();
    gfx.text.DestroyText();
    sdl.TTF_CloseFont(gfx.font);

    sdl.SDL_DestroyWindow(gfx.window);
    sdl.SDL_DestroyRenderer(gfx.renderer);

    sdl.SDL_Quit();

    sdlData = null;
  }

  // This is allocated statically so no need to free manually
  //if (colors) |pal|
  //{
  //  gpa.free(pal);
  //}
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
    minSize = @min(minSize, Level.Coord{32, 32});
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
  {
    if (!sdl.SDL_SetRenderDrawColorFloat(
      gfx.renderer, fg[0], fg[1], fg[2], 1.0))
    {
      return Error.RenderFail;
    }
  }
}

pub fn drawCh(pos: Level.Coord, ch: Char) Error!void
{
  if (
    @reduce(.Or, pos < @as(Level.Coord, @splat(0))) or
    @reduce(.Or, pos >= size()))
  {
    return;
  }

  if (ncData != null)
  {
    var chSpr: nc.chtype = ch;
    if (chSpr & acsBit > 0)
    {
      chSpr = chSpr & ~acsBit | 0x400000;
    }

    var chColor: c_short = undefined;
    if (nc.attr_get(null, &chColor, null) == nc.ERR)
    {
      return Error.RenderFail;
    }

    var ncChar: nc.cchar_t = undefined;
    if (nc.setcchar(
      &ncChar,
      &[_]c_int{@intCast(ch), 0},
      0,
      chColor,
      null
    ) == nc.ERR)
    {
      return Error.RenderFail;
    }
    // Ignore the error if we're writing to the bottom right corner
    if (
      nc.mvadd_wch(pos[1], pos[0], &ncChar) == nc.ERR and
      @reduce(.Or, pos != size() - @as(Level.Coord, @splat(1))))
    {
      //log.err("Failed to render \'{s}\'({}) to coordinate {}. (win size: {})\n", .{(&@as(u8, @truncate(chSpr)))[0..1], chSpr, pos, size()});
      return Error.RenderFail;
    }
  }

  if (sdlData) |gfx|
  {
    //if (!sdl.SDL_RenderPresent(sdlRenderer))
    //  return Error.RenderFail;
    var charColor: Color = undefined;
    if (!gfx.renderer.GetRenderDrawColorFloat(
      &charColor[0], &charColor[1], &charColor[2], null))
    {
      return error.RenderFail;
    }

    var winSize: @Vector(2, c_int) = undefined;
    if (!gfx.window.GetWindowSize(&winSize[0], &winSize[1]))
    {
      return error.RenderFail;
    }

    //const winSizeFloat: @Vector(2, f32) = @floatFromInt(winSize);
    //const viewSizeFloat: @Vector(2, f32) = @floatFromInt(gfx.viewSize);
    //const charSize: @Vector(2, f32) = .{
    //  winSizeFloat[1] / viewSizeFloat[1] *
    //    gfx.fontRatio,
    //  winSizeFloat[1] / viewSizeFloat[1]
    //};
    
    var unicodeStr: [4]u8 = undefined;
    const len = std.unicode.utf8Encode(ch, &unicodeStr) catch
      return Error.RenderFail;

    if (!gfx.text.SetTextString(&unicodeStr, len))
    {
      return error.RenderFail;
    }

    if (!gfx.text.SetTextColorFloat(
      charColor[0], charColor[1], charColor[2], 1.0))
    {
      return error.RenderFail;
    }
    
    if (!gfx.text.DrawRendererText(
      pos[0] * gfx.glyphSize[0],
      pos[1] * gfx.glyphSize[1]))
    {
      return error.RenderFail;
    }

    //const chSurface = sdl.TTF_RenderGlyph_Solid(
    //  gfx.font,
    //  ch,
    //  .{
    //    .r = @intFromFloat(charColor[0]*255),
    //    .g = @intFromFloat(charColor[1]*255),
    //    .b = @intFromFloat(charColor[2]*255),
    //    .a = 255
    //  },
    //  //.{.r = 0, .g = 0, .b = 0, .a = 255}
    //);
    //defer sdl.SDL_DestroySurface(chSurface);

    //const chTexture: *sdl.SDL_Texture =
    //  sdl.SDL_CreateTextureFromSurface(gfx.renderer, chSurface);
    //defer sdl.SDL_DestroyTexture(chTexture);

    //if (!sdl.SDL_RenderTexture(
    //  gfx.renderer,
    //  chTexture,
    //  &.{
    //    .x = 0,
    //    .y = 0,
    //    .w = @floatFromInt(chTexture.w),
    //    .h = @floatFromInt(chTexture.h)
    //  },
    //  &.{
    //    .x = pos[0] * @floor(charSize[0]),
    //    .y = pos[1] * @floor(charSize[1]),
    //    .w = @ceil(charSize[0]),
    //    .h = @ceil(charSize[1])
    //  }))
    //{
    //  return error.RenderFail;
    //}
  }
}

pub fn drawStr(pos: Level.Coord, str: []const u8) Error!void
{
  if (ncData != null)
  {
    const view = std.unicode.Utf8View.init(str) catch return Error.RenderFail;

    // Iterating through the input is less than ideal, but the alternative would involve converting a []u8 utf8 string to a []wchar utf8 string which I don't know how to do
    var x: u15 = 0;
    var it = view.iterator();
    while (it.nextCodepoint()) |ch|: (x += 1)
    {
      try drawCh(.{pos[0]+x, pos[1]}, ch);
    }

    //if (nc.mvaddnwstr(pos[1], pos[0], str.ptr, @intCast(str.len)) == nc.ERR)
    //  return Error.RenderFail;
  }

  if (sdlData) |gfx|
  {
    var stringColor: Color = undefined;
    if (!gfx.renderer.GetRenderDrawColorFloat(
      &stringColor[0], &stringColor[1], &stringColor[2], null))
    {
      return error.RenderFail;
    }

    var winSize: @Vector(2, c_int) = undefined;
    if (!gfx.window.GetWindowSize(&winSize[0], &winSize[1]))
    {
      return error.RenderFail;
    }

    if (!gfx.text.SetTextString(str.ptr, str.len))
    {
      return error.RenderFail;
    }

    if (!gfx.text.SetTextColorFloat(
      stringColor[0], stringColor[1], stringColor[2], 1.0))
    {
      return error.RenderFail;
    }
    
    if (!gfx.text.DrawRendererText(
      pos[0] * gfx.glyphSize[0],
      pos[1] * gfx.glyphSize[1]))
    {
      return error.RenderFail;
    }
  }
}

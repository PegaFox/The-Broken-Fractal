const std = @import("std");
const Io = std.Io;
const log = std.log;

const graphics = @import("graphics.zig");

const Scene = @import("scene.zig");

const mainspace = @import("main.zig");
const nc = mainspace.nc;
const sdl = mainspace.sdl;

const Key = sdl.SDL_Keycode;
/// An array of null-seperated Key arrays
pub var bindings = std.ArrayList(Key).empty;

/// When key is pressed:
///   Check current key combination against key bindings
///   If key combination is valid:
///     Store action ID
///     When lua API calls for input, return current action ID

/// I'm using a multi-item pointer instead of a slice to save memory. This may need to be changed later if length information is important
const Binding = [*]const Key;
/// This stores an index into the bindings array, saving space and avoiding pointer invalidation
pub const IndexBinding = u16;
pub var inputs = std.HashMapUnmanaged(
  IndexBinding,
  []const u8, 
  struct
  {
    pub fn hash(self: @This(), value: IndexBinding) u64
    {_ = self;

      const keyHashFn = std.hash_map.getAutoHashFn(Key, void);
      const hashHashFn = std.hash_map.getAutoHashFn([2]u64, void);
      var currentHash: u64 = 0;

      // Infinite loop protection
      for (0..3) |i|
      {
        if (bindings.items[value+i] == sdl.SDLK_UNKNOWN)
        {
          break;
        }

        const keyHash = keyHashFn({}, bindings.items[value+i]);
    
        currentHash = hashHashFn({}, .{currentHash, keyHash});
        log.debug("Hash key \'{s}\'({}): {}\n", .{@as(*const [1]u8, @ptrCast(&bindings.items[value+i])), bindings.items[value+i], currentHash});
      }

      return currentHash;
    }

    pub fn eql(self: @This(), a: IndexBinding, b: IndexBinding) bool
    {_ = self;
      // Infinite loop protection
      for (0..3) |i|
      {
        if (bindings.items[a+i] != bindings.items[b+i])
        {
          return false;
        }

        if (bindings.items[a+i] == sdl.SDLK_UNKNOWN)
        {
          break;
        }
      }

      return true;
    }
  },
  80
).empty;

pub const InputPointerCtx = struct
{
  pub fn hash(value: Binding) u64
  {
    const keyHashFn = std.hash_map.getAutoHashFn(Key, void);
    const hashHashFn = std.hash_map.getAutoHashFn([2]u64, void);
    var currentHash: u64 = 0;

    // Infinite loop protection
    for (0..3) |i|
    {
      if (value[i] == sdl.SDLK_UNKNOWN)
      {
        break;
      }

      const keyHash = keyHashFn({}, value[i]);
  
      currentHash = hashHashFn({}, .{currentHash, keyHash});
      //log.debug("Pointer hash key \'{s}\'({}): {}\n", .{@as(*const [1]u8, @ptrCast(&value[i])), value[i], currentHash});
    }

    return currentHash;
  }

  pub fn eql(a: Binding, b: IndexBinding) bool
  {
    // Infinite loop protection
    for (0..3) |i|
    {
      //log.debug(
      //  "Testing \'{s}\'({}) vs \'{s}\'({})\n",
      //  .{
      //    @as(*const [1]u8, @ptrCast(&a[i])), a[i],
      //    @as(*const [1]u8, @ptrCast(&bindings.items[b+i])), bindings.items[b+i]
      //  }
      //);

      if (a[i] != bindings.items[b+i])
      {
        return false;
      }

      if (a[i] == sdl.SDLK_UNKNOWN)
      {
        break;
      }
    }

    return true;
  }
};

const quitEvent = "Quit";

// Currently held keys
var currentSequence: [3]Key = undefined;
var currentSequenceLen: u2 = 0;

/// Blocks until an input is recieved
/// Io is used to get a timestamp for events
pub fn getInput(io: Io) ![]const u8
{
  const input = pollEvent(io) orelse return "";

  switch (std.hash_map.hashString(input))
  {
    std.hash_map.hashString(quitEvent) => mainspace.running = false,
    else => {
      
    },
  }

  return input;
}

/// Io is used to get a timestamp for events
fn pollEvent(io: Io) ?[]const u8
{_ = io;
  if (graphics.sdlData != null)
  {
    var event: sdl.SDL_Event = undefined;

    // Conditional returns on success so we can fetch both events depending on window/terminal focus
    if (sdl.SDL_PollEvent(&event))
    {
      switch (event.type)
      {
        sdl.SDL_EVENT_KEY_DOWN => {
          if (
            event.key.mod & sdl.SDL_KMOD_CTRL > 0 and
            event.key.key == sdl.SDLK_C)
          {
            return quitEvent;
          }

          // TODO: Add modifier key support
          if (inputs.getAdapted(
            &[_:0]Key{event.key.key}, InputPointerCtx)) |eventName|
          {
            return eventName;
          }
        },
        else => {}
      }
    }
  }

  if (graphics.ncData != null)
  {
    const key: c_int = nc.getch();
    
    if (key == -1)
    {
      return null;
    }

    if (key == 3) return quitEvent;

    //const name = nc.keyname(key);
    //log.debug("Key {s} ({}) press\n", .{name, key});

    //log.debug(
    //  "Testing \'{s}\'({}) press\n",
    //  .{@as(*const [1]u8, @ptrCast(&key)), key}
    //);
    // TODO: Add modifier key support
    if (inputs.getAdapted(
      &[_:0]Key{@intCast(key)}, InputPointerCtx)) |eventName|
    {
      return eventName;
    }

    //switch (key)
    //{
    //  3, 26 => .{.quit = .{.type = sdl.SDL_EVENT_QUIT}},
    //  nc.KEY_RESIZE => .{.window = .{
    //    .type = sdl.SDL_EVENT_WINDOW_RESIZED, 
    //    .windowID = 0,
    //    .data1 = nc.COLS,
    //    .data2 = nc.LINES,
    //  }},
    //  31...nc.KEY_RESIZE-1, nc.KEY_RESIZE+1...nc.KEY_MAX => .{// 31 is the first visible ASCII character
    //    .key = .{
    //      .type = sdl.SDL_EVENT_KEY_DOWN,
    //      .windowID = 0,
    //      .which = 0,
    //      //.scancode = sdl.SDL_Keymod: SDL_Scancode = @import("std").mem.zeroes(SDL_Scancode), // I'm not sure how to convert keycodes to scancodes in sdl
    //      .key = std.ascii.toLower(@intCast(key)), // SDL_Keycode uses ascii representation for the first 128 chars (excluding uppercase letters which are handled by the mod field)
    //      .mod = @intCast(
    //        sdl.SDL_KMOD_LSHIFT *
    //        @intFromBool(std.ascii.isUpper(@intCast(key)))
    //      ),
    //      .raw = @intCast(key),
    //      .down = true,
    //      .repeat = false, // We don't know if it's a key repeat, but it doesn't matter much
    //    }
    //  },
    //  else => return null,
    //};

    //event.common.timestamp = @truncate(
    //  @max(0, mainspace.startTime.untilNow(io, .awake).toNanoseconds())
    //);
  }

  return null;
}

pub fn keyFromString(keyName: [:0]const u8) error{InvalidString}!Key
{
  const key = sdl.SDL_GetKeyFromName(keyName);

  if (key == sdl.SDLK_UNKNOWN)
  {
    return error.InvalidString;
  }

  return key;
}

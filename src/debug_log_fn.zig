const std = @import("std");
const Io = std.Io;
const Dir = Io.Dir;

const mainspace = @import("main.zig");

var firstLog = false;

pub fn debugLogFN(
  comptime message_level: std.log.Level,
  comptime scope: @TypeOf(.enum_literal),
  comptime format: []const u8,
  args: anytype,
) void
{
  _ = scope;

  const io = std.Options.debug_io;

  var logFile = Dir.cwd().createFile(
    io,
    "log.log",
    .{.truncate = !firstLog, .lock = .shared}) catch
  {
    std.debug.print("ERROR: Failed to open file\n", .{});
    return;
  };

  var logBuffer: [1024]u8 = undefined;
  var log = logFile.writer(io, &logBuffer);
  log.seekToUnbuffered(
    logFile.length(io) catch
    {
      std.debug.print("ERROR: Failed to append to file\n", .{});
      return;
    }
  ) catch
  {
    std.debug.print("ERROR: Failed to append to file\n", .{});
    return;
  };

  log.interface.printAsciiChar('(', .{}) catch
    std.debug.print("ERROR: Failed to log to file\n", .{});

  mainspace.startTime.untilNow(io, .awake).format(&log.interface) catch
  {
    std.debug.print("ERROR: Failed to append to file\n", .{});
    return;
  };

  log.interface.printAsciiChar(')', .{}) catch
    std.debug.print("ERROR: Failed to log to file\n", .{});

  comptime var levelStr: [message_level.asText().len]u8 =
    message_level.asText()[0..].*;
  log.interface.print(
    std.ascii.upperString(&levelStr, &levelStr) ++ ": " ++ format, args
  ) catch std.debug.print("ERROR: Failed to log to file\n", .{});
  //std.debug.print(std.ascii.upperString(&levelStr, &levelStr) ++ ": " ++ format, args);
  log.interface.flush() catch
    std.debug.print("ERROR: Failed to write to file\n", .{});

  logFile.close(io);
  
  firstLog = true;
}

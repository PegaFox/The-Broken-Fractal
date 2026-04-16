const std = @import("std");
const fs = std.fs;

var firstLog = false;

pub fn debugLogFN(
  comptime message_level: std.log.Level,
  comptime scope: @TypeOf(.enum_literal),
  comptime format: []const u8,
  args: anytype,
) void
{
  _ = scope;

  var logFile = fs.cwd().createFile(
    "log.log", .{.truncate = !firstLog, .lock = .shared}) catch
  {
    std.debug.print("ERROR: Failed to open file\n", .{});
    return;
  };

  logFile.seekFromEnd(0) catch
    std.debug.print("ERROR: Failed to append to file\n", .{});

  var logBuffer: [1024]u8 = undefined;
  var log = logFile.writerStreaming(&logBuffer);

  comptime var levelStr: [message_level.asText().len]u8 =
    message_level.asText()[0..].*;
  log.interface.print(
    std.ascii.upperString(&levelStr, &levelStr) ++ ": " ++ format, args
  ) catch std.debug.print("ERROR: Failed to log to file\n", .{});
  //std.debug.print(std.ascii.upperString(&levelStr, &levelStr) ++ ": " ++ format, args);
  log.interface.flush() catch
    std.debug.print("ERROR: Failed to append to file\n", .{});

  logFile.close();
  
  firstLog = true;
}

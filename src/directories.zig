const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const File = Io.File;
const Dir = Io.Dir;
const log = std.log;

const Scene = @import("scene.zig");

const ECS = @import("ecs");
const WritingScene = @import("scenes/writing.zig");
const mainspace = @import("main.zig");

const SearchPath = enum
{
  Cwd,
  ExeDir,
};
var searchPaths = std.EnumArray(SearchPath, struct {
  arr: [Dir.max_path_bytes]u8, len: usize
}).initFill(.{.arr = @splat(0), .len = 0});

/// Calling this function invalidates previous return values of getPath
/// Caller owns directory handle
pub fn getDir(io: Io, path: []const []const u8) !Dir
{
  const fullPath = try getPath(io, path);

  return try Dir.openDirAbsolute(io, fullPath, .{.iterate = true});
}

var pathBuffer: [Dir.max_path_bytes]u8 = undefined;
/// Calling this function invalidates previous return values of getPath
pub fn getPath(io: Io, path: []const []const u8) ![:0]const u8
{
  var osPathBuffer: [Dir.max_path_bytes]u8 = undefined;
  var osPathAllocator = std.heap.FixedBufferAllocator.init(&osPathBuffer);

  // This is stored in osPathBuffer so we don't need to free it manually
  const osPath =
    std.fs.path.join(osPathAllocator.allocator(), path) catch unreachable;
  log.info("Searching for sub path \"{s}\"\n", .{osPath});

  for (0.., searchPaths.values) |p, searchPath|
  {
    log.info(
      "Checking search path \"{s}\"\n",
      .{searchPath.arr[0..searchPath.len]}
    );

    const dir =
      Dir.openDirAbsolute(io, searchPath.arr[0..searchPath.len], .{}) catch |e|
        switch (e)
        {
          error.AccessDenied, error.PermissionDenied => return e,
          else => unreachable,
        };
    defer dir.close(io);

    // Create the path at the final search directory if all previous fail
    if (p < searchPaths.values.len-1)
    {
      dir.access(io, osPath, .{}) catch continue;
    } else
    {
      dir.createDirPath(io, osPath) catch continue;
    }

    var pathAllocator = std.heap.FixedBufferAllocator.init(&pathBuffer);
    return
      std.fs.path.joinZ(
        pathAllocator.allocator(), &.{searchPath.arr[0..searchPath.len], osPath}
      );
  }

  return error.FileNotFound;
}

/// Populates searchPaths
pub fn initSearchPaths(io: Io) void
{
  searchPaths.getPtr(.Cwd).len =
    std.process.currentPath(io, &searchPaths.getPtr(.Cwd).arr) catch 0;
  searchPaths.getPtr(.ExeDir).len =
    std.process.executableDirPath(io, &searchPaths.getPtr(.ExeDir).arr) catch 0;
}

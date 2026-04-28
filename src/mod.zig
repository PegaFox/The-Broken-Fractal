const std = @import("std");
const log = std.log;
const Io = std.Io;
const path = std.fs.path;
const Dir = Io.Dir;
const File = Io.File;

const directories = @import("directories.zig");

pub fn reloadAll(io: Io) !void
{
  try unloadAll(io);
  try loadAll(io);
}

pub fn reload(name: []const u8) void
{
  unload(name);
  load(name);
}

pub fn loadAll(io: Io) !void
{
  var it = try DirIterator.init(io);
  defer it.deinit(io);
  while (try it.next(io)) |mod|
  {
    try load(io, mod);
  }
}

pub fn unloadAll(io: Io) void
{_ = io;
  //var it = try DirIterator.init(io);
  //defer it.deinit(io);
  //while (try it.next(io)) |mod|
  //{
  //  unload(io, mod);
  //}
}

/// Does not close modDir
pub fn load(io: Io, modDir: Dir) !void
{
  
}

/// Does not close modDir
pub fn unload(io: Io, modDir: Dir) void
{
  _ = io;
  _ = modDir;
}

/// Iterates through the mods directory
const DirIterator = struct
{
  rootDir: Dir,
  it: Dir.Iterator,
  currentDir: ?Dir,
 
  pub fn init(io: Io) !@This()
  {
    const modsDir = try directories.getDir(io, &.{"mods"});
    return .{
      .rootDir = modsDir,
      .it = modsDir.iterateAssumeFirstIteration(),
      .currentDir = null,
    };
  }

  pub fn deinit(self: @This(), io: Io) void
  {
    if (self.currentDir) |dir|
    {
      dir.close(io);
    }

    self.rootDir.close(io);
  }

  /// Returned directory is valid until next call or deinit()
  pub fn next(self: *@This(), io: Io) !?Dir
  {
    if (self.currentDir) |dir|
    {
      dir.close(io);
      self.currentDir = null;
    }

    const entry = (self.it.next(io) catch return null) orelse return null;

    self.currentDir = switch (entry.kind)
    {
      .directory => try self.rootDir.openDir(io, entry.name, .{}),
      //.sym_link,
      .file => dir:{
        const zipFile = try self.rootDir.openFile(io, entry.name, .{});
        var readerBuffer: [1024]u8 = undefined;
        var zipFileReader = zipFile.reader(io, &readerBuffer);

        const resultDir = try directories.getDir(io, &.{"cache"});
        defer resultDir.close(io);

        try resultDir.deleteTree(io, path.stem(entry.name));
        try std.zip.extract(resultDir, &zipFileReader, .{});

        break:dir try resultDir.openDir(io, path.stem(entry.name), .{});
      },
      else => try self.next(io),
    };

    return self.currentDir;
  }
};

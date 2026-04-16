//! State file format:
//! 
//! - Little endian
//! - 4 byte pointers
//! - Stores current scene
//! - Stores scene states
//! - Stores ECS state
//! - Stores level
//!
//! Header:
//!   Magic number: 'TBFs'
//!   State file version code: u16
//!   Size of header: u32
//!   Current scene ID: u16
//!   Section descriptor array:
//!     Array element:
//!       Section code: [4]u8
//!       Start of section: u32
//!       Size of section: u32
//! Section types:
//!   Writing scene state: 'WRTs'
//!   Cursor position: [2]u8
//!   Buffer width: u8
//!   Writing Buffer entity ID: u16
//!
//!   ECS state: 'ECSs'
//!   Next entity ID: u16
//!   Component array:
//!     Array element:
//!       Component identifier length: u32
//!       Component identifier [Component identifier length]u8
//!       Component size: u32
//!       Component count: u32
//!       Component instance array:
//!         Array element: 
//!           Entity: u16
//!           Value: anytype
//!
//!   Level state: 'WLDs'
//!   Camera position: [2]i16
//!   Object count: u8
//!   Object array:
//!     Array element: u16
//!   Tile array:
//!     Array element:
//!       Position: [2]i16
//!       Tile: u16

const std = @import("std");
const Allocator = std.mem.Allocator;
const fs = std.fs;
const log = std.log;

const Scene = @import("scene.zig");

const ECS = @import("ecs");
const WritingScene = @import("scenes/writing.zig");
const mainspace = @import("main.zig");

fn getDataDir() !fs.Dir
{
  const dataDirName = fs.getAppDataDir(mainspace.allocator.allocator(), "broken_fractal") catch blk: {
    var exePathBuffer: [fs.max_path_bytes]u8 = undefined;

    break :blk try fs.path.join(mainspace.allocator.allocator(), &.{
      fs.selfExeDirPath(&exePathBuffer) catch |e| {
        log.err("Failed to find app data folder {}\n", .{e});
        return e;
      },
      "broken_fractal"
    });
  };

  fs.makeDirAbsolute(dataDirName) catch |e| {
    if (e != fs.Dir.MakeError.PathAlreadyExists)
    {
      log.warn("Failed to make user subfolder {}\n", .{e});
    }
  };

  const dataDir = fs.openDirAbsolute(dataDirName, .{});

  defer mainspace.allocator.allocator().free(dataDirName);

  return dataDir;
}

pub fn saveState() !void
{
  const dataDir = try getDataDir();

  dataDir.makeDir("user") catch |e| {
    if (e != fs.Dir.MakeError.PathAlreadyExists)
    {
      log.warn("Failed to make user subfolder {}\n", .{e});
    }
  };

  const stateFile = dataDir.createFile("user/state.sav", .{.lock = .exclusive}) catch |e| {
    log.err("Failed to open gamestate file {}\n", .{e});
    return e;
  };
  defer stateFile.close();

  var stateWriterBuffer: [1024]u8 = undefined;
  var stateWriter = stateFile.writer(&stateWriterBuffer);
  defer stateWriter.interface.flush() catch {};
  
  try stateWriter.interface.writeAll("TBFs"); // Magic number
  try stateWriter.interface.writeInt(u16, 0, .little); // File version

  const headerSize = 4+2+4+2+(4+4+4)*3;
  try stateWriter.interface.writeInt(u32, headerSize, .little); // Header size
  try stateWriter.interface.writeInt(u16, @intFromEnum(Scene.currentScene.id), .little); // Scene ID

  try stateWriter.interface.writeAll("WRTs"); // Writing state ID
  try stateWriter.interface.writeInt(u32, headerSize, .little); // Writing state section pos

  const writingSectionSize = 4+2+1+2;
  try stateWriter.interface.writeInt(u32, writingSectionSize, .little); // Writing section size

  try stateWriter.interface.writeAll("ECSs"); // ECS state ID
  try stateWriter.interface.writeInt(u32, headerSize+writingSectionSize, .little); // ECS state section pos

  const ecsSectionSize = blk: {
    var size: u32 = 4+2;

    var it = mainspace.ecs.componentTable.iterator();
    while (it.next()) |componentArray|
    {
      size += @intCast(4+componentArray.key_ptr.len+4+4);
      size += @intCast(@as(usize, 2+componentArray.value_ptr.typeSize())*componentArray.value_ptr.count(componentArray.value_ptr.componentArray));
    }

    break :blk size;
  };
  try stateWriter.interface.writeInt(u32, ecsSectionSize, .little); // ECS state section size

  try stateWriter.interface.writeAll("WLDs"); // Level state ID
  try stateWriter.interface.writeInt(u32, headerSize+writingSectionSize+ecsSectionSize, .little); // Level state section pos

  const levelSectionSize = blk: {
    var size: u32 = 4+2+1;

    for (mainspace.level.objects) |object|
    {
      _ = object;
      size += 2;
    }

    var it = mainspace.level.tiles.iterator();
    while (it.next()) |entry|
    {
      _ = entry;
      size += 4+2;
    }

    break :blk size;
  };
  try stateWriter.interface.writeInt(u32, levelSectionSize, .little); // Level state section size

  try stateWriter.interface.writeAll("WRTs"); // Writing state header
  try stateWriter.interface.writeAll(&@as([2]u8, WritingScene.cursorPos)); // Writing state cursor position
}

pub fn loadState() void
{

}

pub fn savePersistantData() void
{

}

pub fn loadPersistant() void
{

}

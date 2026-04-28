const Self = @This();

const std = @import("std");
const log = std.log;

const Level = @import("scenes/level.zig");
const ECS = @import("ecs");
const mainspace = @import("main.zig");

pub const staticData = [_]struct
{
  ch: u8,
}{
  .{.ch = '@'},
};

pub const Type = enum(u1)
{
  Player,
};

id: ECS.Entity.Unmanaged,
/// For multiple objects stacked on one tile
node: std.SinglyLinkedList.Node,

pub fn init(objectType: Type, pos: Level.Coord, components: anytype) Self
{
  const result = Self{
    .id = mainspace.ecs.addEntity(components).id,
    .node = .{.next = null},
  };

  mainspace.ecs.addC(result.id, "objectType", objectType);
  mainspace.ecs.addC(result.id, "pos", pos);

  return result;
}

pub fn getStaticData(object: Self) ?@TypeOf(staticData[0])
{
  const objectType: Type =
    mainspace.ecs.get(object.id, "objectType", Type) orelse return null;

  return staticData[@intFromEnum(objectType)];
}

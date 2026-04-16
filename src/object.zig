const log = @import("std").log;

const ECS = @import("ecs");
const mainspace = @import("main.zig");

pub const staticData = [_]struct
{
  ch: u8,
}{
  .{.ch = '@'},
};

pub const Type = enum(u1) {
  Player,
};

pub fn getStaticData(object: ECS.Entity.Unmanaged) ?@TypeOf(staticData[0])
{
  const objectType: Type =
    mainspace.ecs.getComponent(object, "objectType", Type) orelse return null;

  return staticData[@intFromEnum(objectType)];
}

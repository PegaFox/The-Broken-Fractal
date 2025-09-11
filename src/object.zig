const ECS = @import("ecs");
const mainspace = @import("main.zig");

pub const staticData = [_]struct
{
  ch: u8,
}{
  .{.ch = '@'},
};

pub const Type = enum {
  Player,
};

pub const Pos = @Vector(2, i16);

pub fn getStaticData(object: ECS.Entity) ?@TypeOf(staticData[0])
{
  const tileType: Type = mainspace.ecs.getComponent(object, "objectType", Type) orelse return null;

  return staticData[@intFromEnum(tileType)];
}

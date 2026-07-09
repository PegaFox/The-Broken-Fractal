//! For entities that can receive visual input, requires a 'pos' component

const Self = @This();

const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;
const ViewMap = std.AutoHashMapUnmanaged(Level.Coord, void);

const ECS = @import("ecs");
const tile = @import("tile.zig");
const TileMemory = @import("tile_memory.zig");
const Level = @import("scenes/level.zig");
const mainspace = @import("main.zig");

radius: u16,
view: ViewMap,

//pub fn init(allocator: Allocator, radius: u16) Self
//{
//  return .{
//    .radius = radius,
//    .view = .init(allocator),
//  };
//}
//
//pub fn deinit(self: *Self) void
//{
//  self.view.deinit();
//}

pub fn getView(self: *Self, parent: ECS.Entity.Unmanaged, level: *Level)
  error{MissingComponent, OutOfMemory}!void
{
  self.view.clearRetainingCapacity();

  const parentMemory =
    mainspace.ecs.getComponentPtr(parent, "tileMemory", TileMemory);

  const parentPos =
    mainspace.ecs.getComponent(parent, "pos", Level.Coord) orelse
      return error.MissingComponent;

  try self.shadowCast(level, parentPos, parentMemory);
  //try self.raycast(level, 64, parentPos, parentMemory);
}

pub fn inView(self: Self, pos: Level.Coord) bool
{
  return self.view.contains(pos);
}

fn raycast(
  self: *Self,
  level: *Level,
  rayCount: u16,
  startPos: Level.Coord,
  memory: ?*TileMemory) !void
{
  for (0..rayCount) |r|
  {
    const ang = @as(f32, @floatFromInt(r))/rayCount * std.math.pi*2;

    const rayDir = @Vector(2, f32){@sin(ang), -@cos(ang)};

    try self.complexRaycast(level, startPos, rayDir, memory);
  }
}

fn simpleRaycast(
  self: *Self,
  level: *Level,
  startPos: Level.Coord,
  dir: @Vector(2, f32),
  memory: ?*TileMemory) !void
{
  // Basic casting
  var dis: f32 = 0;
  var rayPos: @Vector(2, f32) = @floatFromInt(startPos);
  while (dis < self.radius): (dis += 1)
  {
    const lookTile = try level.getTile(@intFromFloat(@round(rayPos)));
  
    try self.view.put(
      Level.gpa, @intFromFloat(@round(rayPos)), undefined
    );
    if (memory) |mem|
    {
      try mem.tiles.put(
        Level.gpa, @intFromFloat(@round(rayPos)), lookTile
      );
    }
  
    if (!tile.getStaticData(lookTile).?.walkable)
    {
      break;
    }
  
    rayPos += dir;
  }
}

fn complexRaycast(
  self: *Self,
  level: *Level,
  startPos: Level.Coord,
  dir: @Vector(2, f32),
  memory: ?*TileMemory) !void
{
  const tileDelta = @abs(@as(@Vector(2, f32), @splat(1)) / dir);
  const stepDir: @Vector(2, i2) = blk:{
    const stepFlags: @Vector(2, i3) =
      @intFromBool(dir >= @as(@Vector(2, f32), @splat(0)));
    break:blk @intCast(stepFlags*@Vector(2, i3){2, 2} - @Vector(2, i3){1, 1});
  };
  var rayDelta = @max(@as(@Vector(2, f32), @splat(0)), tileDelta);

  var rayPos = startPos;
  var dis: u16 = 0;
  while (dis < self.radius): (dis += 1) 
  {
    const lookTile = try level.getTile(rayPos);

    try self.view.put(
      Level.gpa, rayPos, undefined
    );
    if (memory) |mem|
    {
      try mem.tiles.put(
        Level.gpa, rayPos, lookTile
      );
    }

    if (!tile.getStaticData(lookTile).?.walkable)
    {
      break;
    }

    if (rayDelta[0] < rayDelta[1]) 
    {
      //ray->hitPos = startPos + rayDir * edgeDelta.x;
      rayDelta[0] += tileDelta[0];
      rayPos[0] += stepDir[0];
      //ray->verticalHit = false;
    } else 
    {
      //ray->hitPos = startPos + rayDir * edgeDelta.y;
      rayDelta[1] += tileDelta[1];
      rayPos[1] += stepDir[1];
      //ray->verticalHit = true;
    }
  }

  //if (ray->verticalHit) 
  //{
  //  ray->dis = (edgeDelta.y - tileDelta.y) + startDis;
  //  // returnValue.hitPos = startPos + rayDir*returnValue.dis;
  //} else 
  //{
  //  ray->dis = (edgeDelta.x - tileDelta.x) + startDis;
  //  // returnValue.hitPos = startPos + rayDir*returnValue.dis;
  //}
}

fn shadowCast(
  self: *Self,
  level: *Level,
  startPos: Level.Coord,
  memory: ?*TileMemory) !void
{
  const Shadow = struct
  {
    startSlope: f32,
    endSlope: f32,
    // Relative to startPos
    line: u15,
    direction: @Vector(2, i2),
  };
  var shadowStack: [16]Shadow = .{
    Shadow{
      .startSlope = -1,
      .endSlope = 1,
      .line = 0,
      // Algorithm assumes x xor y
      .direction = .{0, -1}
    },
    Shadow{
      .startSlope = -1,
      .endSlope = 1,
      .line = 0,
      // Algorithm assumes x xor y
      .direction = .{0, 1}
    },
    Shadow{
      .startSlope = -1,
      .endSlope = 1,
      .line = 0,
      // Algorithm assumes x xor y
      .direction = .{-1, 0}
    },
    Shadow{
      .startSlope = -1,
      .endSlope = 1,
      .line = 0,
      // Algorithm assumes x xor y
      .direction = .{1, 0}
    },
  } ++ @as([12]Shadow, @splat(undefined));
  var shadowTop: [*]Shadow = shadowStack[3..4];

  // Single octant
  while (@intFromPtr(shadowTop) >= @intFromPtr(&shadowStack[0]))
  {
    while (shadowTop[0].line < self.radius): (shadowTop[0].line += 1)
    {
      var col =
        //@as([2]i16, startPos)[@intFromBool(shadowTop[0].direction[1] != 0)] +
        @as(i16, @round(shadowTop[0].startSlope*shadowTop[0].line));
      while (col <= @round(shadowTop[0].endSlope*shadowTop[0].line)): (col += 1)
      {
        const pos: Level.Coord = blk:{
          var pos: [2]i16 = undefined;

          const posFrontIdx = @intFromBool(shadowTop[0].direction[1] != 0);
          pos[posFrontIdx] =
            @as([2]i16, startPos)[posFrontIdx] +
            @as(i16, shadowTop[0].line)*@as([2]i2, shadowTop[0].direction)[posFrontIdx];
          pos[~posFrontIdx] = 
            @as([2]i16, startPos)[~posFrontIdx] + col;
          break:blk pos;
        };
        const lookTile = try level.getTile(pos);

        log.debug(
          "Pos: {} Start Slope: {}, End Slope: {}\n",
          .{pos, shadowTop[0].startSlope, shadowTop[0].endSlope}
        );

        try self.view.put(
          Level.gpa, pos, undefined
        );
        if (memory) |mem|
        {
          try mem.tiles.put(
            Level.gpa, pos, lookTile
          );
        }

        if (!tile.getStaticData(lookTile).?.walkable)
        {
          const offset = @Vector(2, f32){col, @as(i16, shadowTop[0].line)};
          const startSlope = (offset[0]-0.5) / (offset[1]+@as(f32, if (offset[0] > 0) 0.5 else -0.5));
          const endSlope = (offset[0]+0.5) / (offset[1]+@as(f32, if (offset[0] < 0) 0.5 else -0.5));
          //const startSlope = (offset[0]-1) / offset[1];
          //const endSlope = (offset[0]+1) / offset[1];
          log.debug(
            "Hit Offset: {} Start Slope: {} End Slope: {}\n",
            .{offset, startSlope, endSlope}
          );
          // Avoid infinite slopes
          if (shadowTop[0].line == 0)
          {
            break;
          }

          if (shadowTop[0].startSlope > startSlope)
          {
            shadowTop[0].startSlope = endSlope;
          } else if (shadowTop[0].endSlope < endSlope)
          {
            shadowTop[0].endSlope = startSlope;
          } else
          {
            shadowTop[1] = .{
              .startSlope = endSlope,
              .endSlope = shadowTop[0].endSlope,
              .line = shadowTop[0].line,
              .direction = shadowTop[0].direction,
            };
            shadowTop[0].endSlope = startSlope;
            shadowTop += 1;
          }
        }
      }
    }

    shadowTop -= 1;
  }
}

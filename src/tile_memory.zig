//! For entities that need an imperfect memory of the map state (mainly players)

const Level = @import("scenes/level.zig");

tiles: Level.Tilemap,

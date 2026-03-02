const std = @import("std");
const EngineStats = @This();

pub const RenderStats = struct {
    TotalObjects: usize = 0,
    OutputQuadNum: usize = 0,
    OutputGlyphNum: usize = 0,

    pub fn ResetStats(self: *RenderStats) void {
        self.TotalObjects = 0;
        self.OutputQuadNum = 0;
        self.OutputGlyphNum = 0;
    }
};

pub const ECSStats = struct {
    TotalEntities: usize = 0,

    pub fn ResetStats(self: *ECSStats) void {
        self.TotalEntities = 0;
    }
};

pub const WorldStats = struct {
    mRenderStats: RenderStats = .{},
    mECSStats: ECSStats = .{},

    pub fn ResetStats(self: *WorldStats) void {
        self.mRenderStats.ResetStats();
        self.mECSStats.ResetStats();
    }
};

AppTimer: std.time.Timer = undefined,
GameWorldStats: WorldStats = .{},
EditorWorldStats: WorldStats = .{},
SimulateWorldStats: WorldStats = .{},

pub fn ResetStats(self: *EngineStats) void {
    self.GameWorldStats.ResetStats();
    self.EditorWorldStats.ResetStats();
    self.SimulateWorldStats.ResetStats();
}

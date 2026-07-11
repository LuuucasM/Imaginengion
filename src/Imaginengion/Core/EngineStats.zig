const std = @import("std");
const EngineStats = @This();

pub const ShadingStats = struct {
    TotalShadings: usize = 0,
    SurfShadings: usize = 0,
    MedShadings: usize = 0,

    pub fn ResetStats(self: *ShadingStats) void {
        self.TotalShadings = 0;
        self.SurfShadings = 0;
        self.MedShadings = 0;
    }
};

pub const RenderStats = struct {
    TotalObjects: usize = 0,
    OutputQuadNum: usize = 0,
    OutputGlyphNum: usize = 0,
    Shadings: ShadingStats = .{},

    pub fn ResetStats(self: *RenderStats) void {
        self.TotalObjects = 0;
        self.OutputQuadNum = 0;
        self.OutputGlyphNum = 0;
        self.Shadings.ResetStats();
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

AppTimer: std.Io.Timestamp = undefined,
GameWorldStats: WorldStats = .{},
EditorWorldStats: WorldStats = .{},
SimulateWorldStats: WorldStats = .{},

pub fn ResetStats(self: *EngineStats) void {
    self.GameWorldStats.ResetStats();
    self.EditorWorldStats.ResetStats();
    self.SimulateWorldStats.ResetStats();
}

pub fn ImguiRender(self: *EngineStats) void {
    //TODO: move render stats in here to follow new imgui convention
    //where i do the rendering from the structs themselves instead
}

const std = @import("std");
const EngineStats = @This();
const EngineContext = @import("EngineContext.zig");
const WorldManager = @import("WorldManager.zig");
const Tracy = @import("Tracy.zig");
const EntityTagComponent = @import("../ECS/Components.zig").EntityTagComponent;
const ScriptTagComponent = @import("../ECS/Components.zig").ScriptTagComponent;

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

/// How many times something happens a second: Tick each time it happens, Advance with the time passed once a loop. The
/// rate is worked out once a second, from that whole second, so it holds still long enough to be read
pub const RateCounter = struct {
    mCount: u32 = 0,
    /// seconds since the rate was last worked out
    mElapsed: f32 = 0,
    /// how many times a second, over the last whole second
    mRate: f32 = 0,

    pub fn Tick(self: *RateCounter) void {
        self.mCount += 1;
    }

    pub fn Advance(self: *RateCounter, dt: f32) void {
        self.mElapsed += dt;
        if (self.mElapsed < 1.0) return;
        self.mRate = @as(f32, @floatFromInt(self.mCount)) / self.mElapsed;
        self.mCount = 0;
        self.mElapsed = 0;
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
/// The last rendered frame's stats, kept when ResetStats zeroes the frame's: the Stats panel shows these, since a
/// frame's are only complete once it has rendered, which is after the panel has been laid out
LastGameWorldStats: WorldStats = .{},
LastEditorWorldStats: WorldStats = .{},
LastSimulateWorldStats: WorldStats = .{},
/// Passes of the main loop a second. A pass that finds no window image free to draw into skips rendering, so this can
/// be far higher than FrameRate when the GPU is behind
LoopRate: RateCounter = .{},
/// Frames drawn a second: window images acquired to draw into, each of which is shown
FrameRate: RateCounter = .{},
/// Whether this pass of the loop got a window image and rendered
FrameRendered: bool = false,

/// The renderer got a window image to draw this frame into
pub fn FrameAcquired(self: *EngineStats) void {
    self.FrameRate.Tick();
    self.FrameRendered = true;
}

/// Once at the end of each pass of the main loop, with how long it took
pub fn CountLoop(self: *EngineStats, dt: f32) void {
    self.LoopRate.Tick();
    self.LoopRate.Advance(dt);
    self.FrameRate.Advance(dt);
}

pub fn ResetStats(self: *EngineStats) void {
    //a pass that skipped rendering drew nothing, so the last frame that did is kept
    if (self.FrameRendered) {
        self.LastGameWorldStats = self.GameWorldStats;
        self.LastEditorWorldStats = self.EditorWorldStats;
        self.LastSimulateWorldStats = self.SimulateWorldStats;
    }
    self.FrameRendered = false;
    self.GameWorldStats.ResetStats();
    self.EditorWorldStats.ResetStats();
    self.SimulateWorldStats.ResetStats();
}

/// Fills in the stats that describe world state rather than work done during the frame. Runs at the
/// start of the frame, since ResetStats zeroes everything at the end and the Stats panel reads these
/// mid-frame; objects created or destroyed this frame show up from the next one.
pub fn CollectFrameStart(self: *EngineStats, engine_context: *EngineContext) void {
    self.GameWorldStats.mECSStats.TotalEntities = engine_context.mGameWorld.NumEntitiesWith(EntityTagComponent);
    self.EditorWorldStats.mECSStats.TotalEntities = engine_context.mEditorWorld.NumEntitiesWith(EntityTagComponent);
    self.SimulateWorldStats.mECSStats.TotalEntities = engine_context.mSimulateWorld.NumEntitiesWith(EntityTagComponent);
}

/// Sends this frame's stats to Tracy as plots. Runs once at the very end of the frame, before the
/// frame arena and the stats are reset, so it sees everything the frame did.
pub fn EmitPlots(self: EngineStats, engine_context: *EngineContext) void {
    //the counts below are cheap but not free, so skip them outright when there is nowhere to send them
    if (!Tracy.enable_tracy) return;

    //the arena keeps its memory between frames (retain_capacity), so this is the largest any frame
    //has needed so far: it only grows, and a jump marks the frame that set a new high
    Tracy.Plot("Frame Arena Capacity", .{ .format = .Memory }, engine_context._Internal.FrameArena.queryCapacity());

    //the editor world only holds editor objects like the viewport camera and is never rendered as a
    //world of its own, so its render stats would be a flat zero
    PlotWorld("Game", self.GameWorldStats, &engine_context.mGameWorld);
    PlotWorld("Simulate", self.SimulateWorldStats, &engine_context.mSimulateWorld);
}

fn PlotWorld(comptime prefix: [:0]const u8, stats: WorldStats, world: *WorldManager) void {
    Tracy.Plot(prefix ++ "/Entities", .{ .color = 0x4CAF50 }, stats.mECSStats.TotalEntities);
    Tracy.Plot(prefix ++ "/Scripts", .{ .color = 0x9C27B0 }, world.NumEntitiesWith(ScriptTagComponent));
    Tracy.Plot(prefix ++ "/Render Objects", .{ .color = 0x2196F3 }, stats.mRenderStats.TotalObjects);
    Tracy.Plot(prefix ++ "/Quads", .{ .color = 0x03A9F4 }, stats.mRenderStats.OutputQuadNum);
    Tracy.Plot(prefix ++ "/Glyphs", .{ .color = 0x00BCD4 }, stats.mRenderStats.OutputGlyphNum);
    Tracy.Plot(prefix ++ "/Shadings", .{ .color = 0xFF9800 }, stats.mRenderStats.Shadings.TotalShadings);
}


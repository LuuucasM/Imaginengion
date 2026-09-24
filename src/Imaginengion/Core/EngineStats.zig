const std = @import("std");
const EngineStats = @This();
const ImguiManager = @import("../Imgui/Imgui.zig");
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

    pub fn ImguiRender(self: ShadingStats, frame_allocator: std.mem.Allocator) !void {
        const total_shadings = try std.fmt.allocPrintSentinel(frame_allocator, "\t\t\tTotal Shadings: {d}\n", .{self.TotalShadings}, 0);
        try ImguiManager.RenderText(total_shadings);
        const surf_shadings = try std.fmt.allocPrintSentinel(frame_allocator, "\t\t\tSurface shadings: {d}", .{self.SurfShadings}, 0);
        try ImguiManager.RenderText(surf_shadings);
        const med_shadings = try std.fmt.allocPrintSentinel(frame_allocator, "\t\t\tMedium Shadings: {d}", .{self.MedShadings}, 0);
        try ImguiManager.RenderText(med_shadings);
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

    pub fn ImguiRender(self: RenderStats, frame_allocator: std.mem.Allocator) !void {
        const total_obj_text = try std.fmt.allocPrintSentinel(frame_allocator, "\t\tTotal Objects: {d}\n", .{self.TotalObjects}, 0);
        try ImguiManager.RenderText(total_obj_text);

        const output_quad_text = try std.fmt.allocPrintSentinel(frame_allocator, "\t\tOutput Quad Num: {d}\n", .{self.OutputQuadNum}, 0);
        try ImguiManager.RenderText(output_quad_text);

        const output_glyph_text = try std.fmt.allocPrintSentinel(frame_allocator, "\t\tOutput Glyph Num: {d}\n", .{self.OutputGlyphNum}, 0);
        try ImguiManager.RenderText(output_glyph_text);

        try ImguiManager.RenderText("\t\tShading Data: \n");
        try self.Shadings.ImguiRender(frame_allocator);
    }
};

pub const ECSStats = struct {
    TotalEntities: usize = 0,

    pub fn ResetStats(self: *ECSStats) void {
        self.TotalEntities = 0;
    }

    pub fn ImguiRender(self: ECSStats, frame_allocator: std.mem.Allocator) !void {
        const total_entities_text = try std.fmt.allocPrintSentinel(frame_allocator, "\t\tTotal Entities: {d}\n", .{self.TotalEntities}, 0);
        try ImguiManager.RenderText(total_entities_text);
    }
};

pub const WorldStats = struct {
    mRenderStats: RenderStats = .{},
    mECSStats: ECSStats = .{},

    pub fn ResetStats(self: *WorldStats) void {
        self.mRenderStats.ResetStats();
        self.mECSStats.ResetStats();
    }

    pub fn ImguiRender(self: WorldStats, frame_allocator: std.mem.Allocator) !void {
        try ImguiManager.RenderText("\tRender Data: \n");
        try self.mRenderStats.ImguiRender(frame_allocator);
        try ImguiManager.RenderText("\tECS Data: \n");
        try self.mECSStats.ImguiRender(frame_allocator);
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

pub fn ImguiRender(self: EngineStats, frame_allocator: std.mem.Allocator) !void {
    try ImguiManager.RenderText("Game World Data: \n");
    try self.GameWorldStats.ImguiRender(frame_allocator);
    try ImguiManager.RenderText("Editor World Data: \n");
    try self.EditorWorldStats.ImguiRender(frame_allocator);
    try ImguiManager.RenderText("Simulate World Data: \n");
    try self.SimulateWorldStats.ImguiRender(frame_allocator);
}

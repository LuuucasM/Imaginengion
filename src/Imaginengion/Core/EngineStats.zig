const std = @import("std");
const EngineStats = @This();
const ImguiManager = @import("../Imgui/Imgui.zig");
const EngineContext = @import("EngineContext.zig");

pub const ShadingStats = struct {
    TotalShadings: usize = 0,
    SurfShadings: usize = 0,
    MedShadings: usize = 0,

    pub fn ResetStats(self: *ShadingStats) void {
        self.TotalShadings = 0;
        self.SurfShadings = 0;
        self.MedShadings = 0;
    }

    pub fn ImguiRender(self: ShadingStats, frame_allocator: std.mem.Allocator) void {
        const total_shadings = try std.fmt.allocPrintSentinel(frame_allocator, "\t\t\tTotal Shadings: {d}\n", .{self.TotalShadings}, 0);
        ImguiManager.RenderText(total_shadings);
        const surf_shadings = try std.fmt.allocPrintSentinel(frame_allocator, "\t\t\tSurface shadings", .{self.SurfShadings}, 0);
        ImguiManager.RenderText(surf_shadings);
        const med_shadings = try std.fmt.allocPrintSentinel(frame_allocator, "\t\t\tMedium Shadings", .{self.MedShadings}, 0);
        ImguiManager.RenderText(med_shadings);
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

    pub fn ImguiRender(self: RenderStats, frame_allocator: std.mem.Allocator) void {
        const total_obj_text = try std.fmt.allocPrintSentinel(frame_allocator, "\t\tTotal Objects: {d}\n", .{self.TotalObjects}, 0);
        ImguiManager.RenderText(total_obj_text);

        const output_quad_text = try std.fmt.allocPrintSentinel(frame_allocator, "\t\tOutput Quad Num: {d}\n", .{self.OutputQuadNum}, 0);
        ImguiManager.RenderText(output_quad_text);

        const output_glyph_text = try std.fmt.allocPrintSentinel(frame_allocator, "\t\tOutput Glyph Num: {d}\n", .{self.OutputGlyphNum}, 0);
        ImguiManager.RenderText(output_glyph_text);

        ImguiManager.RenderText("\t\tShading Data: \n");
        self.mShadingStats.ImguiRender(frame_allocator);
    }
};

pub const ECSStats = struct {
    TotalEntities: usize = 0,

    pub fn ResetStats(self: *ECSStats) void {
        self.TotalEntities = 0;
    }

    pub fn ImguiRender(self: ECSStats, frame_allocator: std.mem.Allocator) void {
        const total_entities_text = try std.fmt.allocPrintSentinel(frame_allocator, "\t\tTotal Entities: {d}\n", .{self.TotalEntities}, 0);
        ImguiManager.RenderText(total_entities_text);
    }
};

pub const WorldStats = struct {
    mRenderStats: RenderStats = .{},
    mECSStats: ECSStats = .{},

    pub fn ResetStats(self: *WorldStats) void {
        self.mRenderStats.ResetStats();
        self.mECSStats.ResetStats();
    }

    pub fn ImguiRender(self: WorldStats, frame_allocator: std.mem.Allocator) void {
        ImguiManager.RenderText("\tRender Data: \n");
        self.mRenderStats.ImguiRender(frame_allocator);
        ImguiManager.RenderText("\tECS Data: \n");
        self.mECSStats.ImguiRender(frame_allocator);
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

pub fn ImguiRender(self: EngineStats, frame_allocator: std.mem.Allocator) void {
    ImguiManager.RenderText("Game World Data: \n");
    self.GameWorldStats.ImguiRender(frame_allocator);
    ImguiManager.RenderText("Editor World Data: \n");
    self.EditorWorldStats.ImguiRender(frame_allocator);
    ImguiManager.RenderText("Simulate World Data: \n");
    self.SimulateWorldStats.ImguiRender(frame_allocator);
}

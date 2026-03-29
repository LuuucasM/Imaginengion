const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const StatsPanel = @This();
const EngineStats = @import("../Core/EngineStats.zig");

_P_Open: bool = false,

pub fn Init(self: StatsPanel) void {
    _ = self;
}

pub fn OnImguiRender(self: StatsPanel, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("StatsPanel OIR", @src());
    defer zone.Deinit();

    if (self._P_Open == false) return;
    _ = imgui.igBegin("Stats", null, 0);
    defer imgui.igEnd();

    const frame_allocator = engine_context.FrameAllocator();
    const engine_stats = engine_context.mEngineStats;

    //DELTA TIME STUFF
    const dt = engine_context.mDT;
    const frame_text = try std.fmt.allocPrint(frame_allocator, "Frame Data: \n", .{});
    imgui.igTextUnformatted(frame_text.ptr, frame_text.ptr + frame_text.len);

    const us_time = std.time.us_per_s * dt;
    const us_text = try std.fmt.allocPrint(frame_allocator, "\tDelta time in micro seconds: {d:.0}\n", .{us_time});
    imgui.igTextUnformatted(us_text.ptr, us_text.ptr + us_text.len);

    const s_text = try std.fmt.allocPrint(frame_allocator, "\tDelta time in seconds: {d:.5}\n", .{dt});
    imgui.igTextUnformatted(s_text.ptr, s_text.ptr + s_text.len);

    const fps = 1.0 / dt;
    const fps_text = try std.fmt.allocPrint(frame_allocator, "\tFPS: {d:.0}\n", .{fps});
    imgui.igTextUnformatted(fps_text.ptr, fps_text.ptr + fps_text.len);

    imgui.igSeparator();

    //WORLD STATS
    const game_world_text = try std.fmt.allocPrint(frame_allocator, "Game World Data: \n", .{});
    imgui.igTextUnformatted(game_world_text.ptr, game_world_text.ptr + game_world_text.len);
    try RenderWorldStats(frame_allocator, engine_stats.GameWorldStats);
    imgui.igSeparator();

    const sim_world_text = try std.fmt.allocPrint(frame_allocator, "Simulate World Data: \n", .{});
    imgui.igTextUnformatted(sim_world_text.ptr, sim_world_text.ptr + sim_world_text.len);
    try RenderWorldStats(frame_allocator, engine_stats.SimulateWorldStats);
    imgui.igSeparator();

    const editor_world_text = try std.fmt.allocPrint(frame_allocator, "Editor World Data: \n", .{});
    imgui.igTextUnformatted(editor_world_text.ptr, editor_world_text.ptr + editor_world_text.len);
    try RenderWorldStats(frame_allocator, engine_stats.EditorWorldStats);
}
pub fn OnTogglePanelEvent(self: *StatsPanel) void {
    self._P_Open = !self._P_Open;
}

fn RenderWorldStats(frame_allocator: std.mem.Allocator, world_stats: EngineStats.WorldStats) !void {
    const render_render_Text = try std.fmt.allocPrint(frame_allocator, "\tRender Data: \n", .{});
    imgui.igTextUnformatted(render_render_Text.ptr, render_render_Text.ptr + render_render_Text.len);
    try RenderRenderStats(frame_allocator, world_stats.mRenderStats);

    const render_ecs_stats = try std.fmt.allocPrint(frame_allocator, "\tECS Data: \n", .{});
    imgui.igTextUnformatted(render_ecs_stats.ptr, render_ecs_stats.ptr + render_ecs_stats.len);
    try RenderECSStats(frame_allocator, world_stats.mECSStats);
}

fn RenderRenderStats(frame_allocator: std.mem.Allocator, render_stats: EngineStats.RenderStats) !void {
    const total_obj_text = try std.fmt.allocPrint(frame_allocator, "\t\tTotal Objects: {d}\n", .{render_stats.TotalObjects});
    imgui.igTextUnformatted(total_obj_text.ptr, total_obj_text.ptr + total_obj_text.len);

    const output_quad_text = try std.fmt.allocPrint(frame_allocator, "\t\tOutput Quad Num: {d}\n", .{render_stats.OutputQuadNum});
    imgui.igTextUnformatted(output_quad_text.ptr, output_quad_text.ptr + output_quad_text.len);

    const output_glyph_text = try std.fmt.allocPrint(frame_allocator, "\t\tOutput Glyph Num: {d}\n", .{render_stats.OutputGlyphNum});
    imgui.igTextUnformatted(output_glyph_text.ptr, output_glyph_text.ptr + output_glyph_text.len);
}

fn RenderECSStats(frame_allocator: std.mem.Allocator, ecs_stats: EngineStats.ECSStats) !void {
    const total_entities_text = try std.fmt.allocPrint(frame_allocator, "\t\tTotal Entities: {d}\n", .{ecs_stats.TotalEntities});
    imgui.igTextUnformatted(total_entities_text.ptr, total_entities_text.ptr + total_entities_text.len);
}

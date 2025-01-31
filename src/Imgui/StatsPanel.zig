const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const ImguiEvent = @import("ImguiEvent.zig").ImguiEvent;
const RenderStats = @import("../Renderer/Renderer.zig").RenderStats;
const StatsPanel = @This();

_P_Open: bool,

pub fn Init() StatsPanel {
    return StatsPanel{
        ._P_Open = false,
    };
}

pub fn OnImguiRender(self: StatsPanel, dt: f64, render_stats: RenderStats) !void {
    if (self._P_Open == false) return;
    _ = imgui.igBegin("Stats", null, 0);
    defer imgui.igEnd();

    var buffer: [260]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    const frame_text = try std.fmt.allocPrint(allocator, "Frame Data: \n", .{});
    imgui.igTextUnformatted(frame_text.ptr, frame_text.ptr + frame_text.len);

    const ms_text = try std.fmt.allocPrint(allocator, "\tDelta time: {d:.2}\n", .{dt});
    imgui.igTextUnformatted(ms_text.ptr, ms_text.ptr + ms_text.len);

    const fps = std.time.ms_per_s / dt;
    const fps_text = try std.fmt.allocPrint(allocator, "\tFPS: {d:.2}\n", .{fps});
    imgui.igTextUnformatted(fps_text.ptr, fps_text.ptr + fps_text.len);

    imgui.igSeparator();

    const render_text = try std.fmt.allocPrint(allocator, "Render Data: \n", .{});
    imgui.igTextUnformatted(render_text.ptr, render_text.ptr + render_text.len);

    const render_tri_text = try std.fmt.allocPrint(allocator, "\tTotal Triangles: {d} \n", .{render_stats.mTriCount});
    imgui.igTextUnformatted(render_tri_text.ptr, render_tri_text.ptr + render_tri_text.len);

    const render_vert_text = try std.fmt.allocPrint(allocator, "\tTotal Verticies: {d} \n", .{render_stats.mVertexCount});
    imgui.igTextUnformatted(render_vert_text.ptr, render_vert_text.ptr + render_vert_text.len);

    const render_ind_text = try std.fmt.allocPrint(allocator, "\tTotal Indices: {d} \n", .{render_stats.mIndicesCount});
    imgui.igTextUnformatted(render_ind_text.ptr, render_ind_text.ptr + render_ind_text.len);

    const render_sprite_text = try std.fmt.allocPrint(allocator, "\tTotal Sprites: {d} \n", .{render_stats.mSpriteNum});
    imgui.igTextUnformatted(render_sprite_text.ptr, render_sprite_text.ptr + render_sprite_text.len);

    const render_circle_text = try std.fmt.allocPrint(allocator, "\tTotal Circles: {d} \n", .{render_stats.mCircleNum});
    imgui.igTextUnformatted(render_circle_text.ptr, render_circle_text.ptr + render_circle_text.len);

    const render_eline_text = try std.fmt.allocPrint(allocator, "\tTotal Editor Lines: {d} \n", .{render_stats.mELineNum});
    imgui.igTextUnformatted(render_eline_text.ptr, render_eline_text.ptr + render_eline_text.len);
}

pub fn OnImguiEvent(self: *StatsPanel, event: *ImguiEvent) void {
    switch (event.*) {
        .ET_TogglePanelEvent => self.OnTogglePanelEvent(),
        else => @panic("This event isnt handeled yet in StatsPanel!\n"),
    }
}

pub fn OnTogglePanelEvent(self: *StatsPanel) void {
    self._P_Open = !self._P_Open;
}

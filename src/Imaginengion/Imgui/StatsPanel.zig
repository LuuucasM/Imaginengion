const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const ImguiEvent = @import("../Events/ImguiEvent.zig").ImguiEvent;
const RenderStats = @import("../Renderer/Renderer.zig").RenderStats;
const Tracy = @import("../Core/Tracy.zig");
const StatsPanel = @This();

_P_Open: bool,

pub fn Init() StatsPanel {
    return StatsPanel{
        ._P_Open = false,
    };
}

pub fn OnImguiRender(self: StatsPanel, dt: f64, render_stats: RenderStats) !void {
    const zone = Tracy.ZoneInit("StatsPanel OIR", @src());
    defer zone.Deinit();

    if (self._P_Open == false) return;
    _ = imgui.igBegin("Stats", null, 0);
    defer imgui.igEnd();

    var buffer: [260]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    const frame_text = try std.fmt.allocPrint(allocator, "Frame Data: \n", .{});
    imgui.igTextUnformatted(frame_text.ptr, frame_text.ptr + frame_text.len);

    const us_time = std.time.us_per_s * dt;
    const us_text = try std.fmt.allocPrint(allocator, "\tDelta time in micro seconds: {d:.0}\n", .{us_time});
    imgui.igTextUnformatted(us_text.ptr, us_text.ptr + us_text.len);

    const fps = 1.0 / dt;
    const fps_text = try std.fmt.allocPrint(allocator, "\tFPS: {d:.0}\n", .{fps});
    imgui.igTextUnformatted(fps_text.ptr, fps_text.ptr + fps_text.len);

    imgui.igSeparator();

    const render_text = try std.fmt.allocPrint(allocator, "Render Data: \n", .{});
    imgui.igTextUnformatted(render_text.ptr, render_text.ptr + render_text.len);

    const render_quad_text = try std.fmt.allocPrint(allocator, "\tTotal Triangles: {d} \n", .{render_stats.mQuadNum});
    imgui.igTextUnformatted(render_quad_text.ptr, render_quad_text.ptr + render_quad_text.len);
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

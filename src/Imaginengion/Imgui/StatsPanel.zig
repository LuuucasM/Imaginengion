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
    engine_context.mEngineStats.ImguiRender(frame_allocator);
}
pub fn OnTogglePanelEvent(self: *StatsPanel) void {
    self._P_Open = !self._P_Open;
}

const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const ImguiEvent = @import("ImguiEvent.zig").ImguiEvent;
const StatsPanel = @This();

_P_Open: bool,

pub fn Init() StatsPanel {
    return StatsPanel{
        ._P_Open = false,
    };
}

pub fn OnImguiRender(self: StatsPanel, dt: f64) !void {
    if (self._P_Open == false) return;
    _ = imgui.igBegin("Stats", null, 0);
    defer imgui.igEnd();

    var buffer: [260]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);

    const ms_text = try std.fmt.allocPrint(fba.allocator(), "Delta time: {d:.2}\n", .{dt});
    imgui.igTextUnformatted(ms_text.ptr, ms_text.ptr + ms_text.len);

    const fps = std.time.ms_per_s / dt;
    const fps_text = try std.fmt.allocPrint(fba.allocator(), "FPS: {d:.2}\n", .{fps});
    imgui.igTextUnformatted(fps_text.ptr, fps_text.ptr + fps_text.len);
}

pub fn OnImguiEvent(self: *StatsPanel, event: *ImguiEvent) void {
    switch (event.*) {
        .ET_TogglePanelEvent => self.OnTogglePanelEvent(),
        else => @panic("This event isnt handeled yet in StatsPanel!\n"),
    }
}

fn OnTogglePanelEvent(self: *StatsPanel) void {
    self._P_Open = !self._P_Open;
}
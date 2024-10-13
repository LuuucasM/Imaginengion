const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const ImguiEvent = @import("ImguiEvent.zig").ImguiEvent;
const StatsPanel = @This();

_P_Open: bool = false,

pub fn Init(self: *StatsPanel) void {
    self._P_Open = false;
}

pub fn OnImguiRender(self: StatsPanel, dt: f64) !void {
    if (self._P_Open == false) return;
    _ = imgui.igBegin("Stats", null, 0);
    defer imgui.igEnd();

    var buffer: [260]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);

    const fps = std.time.ms_per_s / dt;
    const text = try std.fmt.allocPrint(fba.allocator(), "FPS: {d:.2}\n", .{fps});
    imgui.igTextUnformatted(text.ptr, text.ptr + text.len);
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
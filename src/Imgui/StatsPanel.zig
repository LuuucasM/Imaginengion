const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const ImguiEvent = @import("ImguiEvent.zig").ImguiEvent;
const StatsPanel = @This();

_P_Open: bool = true,

pub fn Init(self: *StatsPanel) void {
    self._P_Open = true;
}

pub fn OnImguiRender(self: StatsPanel) void {
    if (self._P_Open == false) return;
    _ = imgui.igBegin("Stats", null, 0);
    defer imgui.igEnd();
}

pub fn OnImguiEvent(self: *StatsPanel, event: *ImguiEvent) void {
    switch (event.*) {
        .ET_TogglePanelEvent => self._P_Open = !self._P_Open,
        .ET_NewProjectEvent => {
            std.debug.print("not impelmeneted yet :)\n", .{});
        },
    }
}

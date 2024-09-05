const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const ImguiEvent = @import("ImguiEvent.zig").ImguiEvent;
const PropertiesPanel = @This();

_P_Open: bool = true,
//HoveredEntity

pub fn Init(self: *PropertiesPanel) void {
    self._P_Open = true;
}

pub fn OnImguiRender(self: PropertiesPanel) void {
    if (self._P_Open == false) return;
    _ = imgui.igBegin("Properties", null, 0);
    defer imgui.igEnd();
}

pub fn OnImguiEvent(self: *PropertiesPanel, event: *ImguiEvent) void {
    switch (event.*) {
        .ET_TogglePanelEvent => self._P_Open = !self._P_Open,
        .ET_NewProjectEvent => {
            std.debug.print("not impelmeneted yet :)", .{});
        },
    }
}

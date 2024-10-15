const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const ImguiEvent = @import("ImguiEvent.zig").ImguiEvent;
const ScenePanel = @This();

_P_Open: bool,
//HoveredEntity

pub fn Init() ScenePanel {
    return ScenePanel{
        ._P_Open = true,
    };
}

pub fn OnImguiRender(self: ScenePanel) void {
    if (self._P_Open == false) return;
    _ = imgui.igBegin("Scene", null, 0);
    defer imgui.igEnd();
}
pub fn OnImguiEvent(self: *ScenePanel, event: *ImguiEvent) void {
    switch (event.*) {
        .ET_TogglePanelEvent => self.OnTogglePanelEvent(),
        else => @panic("This event is handled yet in ScenePanel!\n"),
    }
}

fn OnTogglePanelEvent(self: *ScenePanel) void {
    self._P_Open = !self._P_Open;
}
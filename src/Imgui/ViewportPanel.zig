const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const ImguiEvent = @import("ImguiEvent.zig").ImguiEvent;
const ViewportPanel = @This();

_P_Open: bool = true,
//EditorCamera: *EditorCamera
//ViewportFocus: bool
//ViewportHovered: bool
//ViewportSize: vec2
//ViewportBounds: [2]vec2
//HoveredEntity: EntityID
//SceneState: enum
//_SceneManager: SceneManager

pub fn Init(self: *ViewportPanel) void {
    self._P_Open = true;
}

pub fn OnImguiRender(self: ViewportPanel) void {
    if (self._P_Open == true) {
        _ = imgui.igBegin("Viewport", null, 0);
        imgui.igEnd();
    }
}

pub fn OnImguiEvent(self: *ViewportPanel, event: *ImguiEvent) void {
    switch (event.*) {
        .ET_TogglePanelEvent => {
            if (self._P_Open == true) {
                self._P_Open = false;
            } else {
                self._P_Open = true;
            }
        },
        .ET_NewProjectEvent => {
            std.debug.print("not impelmeneted yet :)", .{});
        },
    }
}

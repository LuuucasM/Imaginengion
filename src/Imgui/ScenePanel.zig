const std = @import("std");
const imgui = @import("../Core/CImports.zig").imgui;
const ImguiEvent = @import("ImguiEvent.zig").ImguiEvent;
const SceneLayer = @import("../Scene/SceneLayer.zig");
const Entity = @import("../ECS/Entity.zig");
const ScenePanel = @This();

mIsVisible: bool,
mSelectedScene: ?SceneLayer,
mSelectedEntity: ?Entity,
//mSceneStackRef: *const std.ArrayList(SceneLayer),

pub fn Init() ScenePanel {
    return ScenePanel{
        .mIsVisible = true,
        .mSelectedScene = null,
        .mSelectedEntity = null,
    };
}

pub fn OnImguiRender(self: ScenePanel) void {
    if (self.mIsVisible == false) return;
    _ = imgui.igBegin("Scenes", null, 0);
    defer imgui.igEnd();
}
pub fn OnImguiEvent(self: *ScenePanel, event: *ImguiEvent) void {
    switch (event.*) {
        .ET_TogglePanelEvent => self.OnTogglePanelEvent(),
        else => @panic("This event is handled yet in ScenePanel!\n"),
    }
}

fn OnTogglePanelEvent(self: *ScenePanel) void {
    self.mIsVisible = !self.mIsVisible;
}

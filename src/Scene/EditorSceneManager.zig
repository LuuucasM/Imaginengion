const std = @import("std");
const ECSManager = @import("../ECS/ECSManager.zig");
const SceneLayer = @import("SceneLayer.zig");
const SceneManager = @This();
//_FrameBuffer: *FrameBuffer,
_ActiveScene: *SceneLayer,
_SceneState: ESceneState,
_ViewportWidth: u32,
_ViewportHeight: u32,
_ECSManager: ECSManager = .{},

pub const ESceneState = enum {
    Stop,
    Play,
};

pub fn Init(self: *SceneManager) void {
    self._ECSManager.Init();
}

pub fn Deinit(self: *SceneManager) void {
    self._ECSManager.Deinit();
}

//pub fn AddOverlay
//pub fn AddGameLayer

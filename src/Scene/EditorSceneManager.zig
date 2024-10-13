const std = @import("std");
const ECSManager = @import("../ECS/ECSManager.zig");
const SceneManager = @This();
_FrameBuffer: *FrameBuffer,
_ActiveScene: *Scene,
_SceneState: SceneState,
_ViewportWidth: u32,
_ViewportHeight: u32,

pub const ESceneState = enum{
    Stop,
    Play,
}

_ECSManager: ECSManager = .{},

pub fn Init(self: *SceneManager, EngineAllocator: std.mem.Allocator) void {
    self._ECSManager.Init();
}

pub fn Deinit(self: *SceneManager) void {
    self._ECSManager.Deinit();
}


//pub fn AddOverlay
//pub fn AddGameLayer
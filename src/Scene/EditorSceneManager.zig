const std = @import("std");
const ECSManager = @import("../ECS/ECSManager.zig");
const SceneManager = @This();
//_FrameBuffer: *FrameBuffer
//_ActiveScene: *Scene
//_EditorScene: *Scene
//_RUntimeScene: *Scene
//_ECSManager: ECSManager

_ECSManager: ECSManager = .{},

pub fn Init(self: *SceneManager, EngineAllocator: std.mem.Allocator) void {
    self._ECSManager.Init();
}

pub fn Deinit(self: *SceneManager) void {
    self._ECSManager.Deinit();
}

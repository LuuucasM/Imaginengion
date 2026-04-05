const std = @import("std");
pub const Type = u32;
pub const NullPlayer: Type = std.math.maxInt(Type);

const EngineContext = @import("../Core/EngineContext.zig");
const SceneManager = @import("../Scene/SceneManager.zig");
const ECSManagerGameMode = SceneManager.ECSManagerGameMode;
const GameMode = @This();

mEntityID: Type = NullPlayer,
mScenemanager: *SceneManager = undefined,

pub fn AddComponent(self: GameMode, engine_allocator: std.mem.Allocator, new_component: anytype) !*@TypeOf(new_component) {
    return try self.mScenemanager.mECSManagerGM.AddComponent(engine_allocator, self.mEntityID, new_component);
}
pub fn RemoveComponent(self: GameMode, comptime component_type: type) !void {
    try self.mScenemanager.mECSManagerGM.RemoveComponent(component_type, self.mEntityID);
}
pub fn GetComponent(self: GameMode, comptime component_type: type) ?*component_type {
    return self.mScenemanager.mECSManagerGM.GetComponent(component_type, self.mEntityID);
}
pub fn HasComponent(self: GameMode, comptime component_type: type) bool {
    return self.mScenemanager.mECSManagerGM.HasComponent(component_type, self.mEntityID);
}

pub fn Duplicate(self: GameMode) !GameMode {
    return try self.mScenemanager.mECSManagerGM.DuplicateEntity(self.mEntityID);
}
pub fn Delete(self: GameMode, engine_context: *EngineContext) !void {
    self.mScenemanager.mECSManagerGM.DestroyEntity(engine_context.EngineAllocator(), self.mEntityID);
}

pub fn IsActive(self: GameMode) bool {
    return self.IsValidID() and self.mScenemanager.mECSManagerGM.IsActiveEntity(self.mEntityID);
}

pub fn IsValidID(self: GameMode) bool {
    return self.mEntityID != NullPlayer;
}

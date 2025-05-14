const std = @import("std");
const ECSManagerScenes = @import("SceneManager.zig").ECSManagerScenes;
const Components = @import("SceneComponents.zig");
const IDComponent = Components.IDComponent;
const NameComponent = Components.NameComponent;
const SceneType = @import("../Scene/SceneManager.zig").SceneType;

pub const NullEntity: SceneType = ~0;
const SceneLayer = @This();

mSceneID: SceneType,
mECSManagerSCRef: *ECSManagerScenes,

pub fn AddComponent(self: SceneLayer, comptime component_type: type, component: ?component_type) !*component_type {
    return try self.mECSManagerSCRef.AddComponent(component_type, self.mSceneID, component);
}
pub fn RemoveComponent(self: SceneLayer, comptime component_type: type) !void {
    try self.mECSManagerSCRef.RemoveComponent(component_type, self.mSceneID);
}
pub fn GetComponent(self: SceneLayer, comptime component_type: type) *component_type {
    return self.mECSManagerSCRef.GetComponent(component_type, self.mSceneID);
}
pub fn HasComponent(self: SceneLayer, comptime component_type: type) bool {
    return self.mECSManagerSCRef.HasComponent(component_type, self.mSceneID);
}
pub fn GetUUID(self: SceneLayer) u128 {
    return self.mECSManagerSCRef.GetComponent(IDComponent, self.mSceneID).*.ID;
}
pub fn GetName(self: SceneLayer) []const u8 {
    return &self.mECSManagerSCRef.GetComponent(NameComponent, self.mSceneID).*.Name;
}
pub fn Duplicate(self: SceneLayer) !SceneLayer {
    return try self.mECSManagerSCRef.DuplicateEntity(self.mSceneID);
}

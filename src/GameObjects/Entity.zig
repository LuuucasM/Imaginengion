const std = @import("std");
const SceneLayer = @import("../Scene/SceneLayer.zig");
const Components = @import("Components.zig");
const IDComponent = Components.IDComponent;
const NameComponent = Components.NameComponent;
const Entity = @This();
pub const NullEntity: u32 = ~0;

mEntityID: u32,
mSceneLayerRef: *SceneLayer,

pub fn AddComponent(self: Entity, comptime component_type: type, component: ?component_type) !*component_type {
    return try self.mSceneLayerRef.mECSManager.AddComponent(component_type, self.mEntityID, component);
}
pub fn RemoveComponent(self: Entity, comptime component_type: type) !void {
    try self.mSceneLayerRef.mECSManager.RemoveComponent(component_type, self.mEntityID);
}
pub fn GetComponent(self: Entity, comptime component_type: type) *component_type {
    return self.mSceneLayerRef.mECSManager.GetComponent(component_type, self.mEntityID);
}
pub fn HasComponent(self: Entity, comptime component_type: type) bool {
    return self.mSceneLayerRef.mECSManager.HasComponent(component_type, self.mEntityID);
}
pub fn GetUUID(self: Entity) u128 {
    return self.mSceneLayerRef.mECSManager.GetComponent(IDComponent, self.mEntityID).*.ID;
}
pub fn GetName(self: Entity) []const u8 {
    return &self.mSceneLayerRef.mECSManager.GetComponent(NameComponent, self.mEntityID).*.Name;
}
pub fn Duplicate(self: Entity) !Entity {
    return try self.mSceneLayerRef.mECSManager.DuplicateEntity(self.mEntityID);
}

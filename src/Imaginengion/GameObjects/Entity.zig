const std = @import("std");
const ECSManager = @import("../ECS/ECSManager.zig");
const Components = @import("Components.zig");
const IDComponent = Components.IDComponent;
const NameComponent = Components.NameComponent;
pub const NullEntity: u32 = ~0;
const Entity = @This();

mEntityID: u32,
mECSManagerRef: *ECSManager,

pub fn AddComponent(self: Entity, comptime component_type: type, component: ?component_type) !*component_type {
    return try self.mECSManagerRef.AddComponent(component_type, self.mEntityID, component);
}
pub fn RemoveComponent(self: Entity, comptime component_type: type) !void {
    try self.mECSManagerRef.RemoveComponent(component_type, self.mEntityID);
}
pub fn GetComponent(self: Entity, comptime component_type: type) *component_type {
    return self.mECSManagerRef.GetComponent(component_type, self.mEntityID);
}
pub fn HasComponent(self: Entity, comptime component_type: type) bool {
    return self.mECSManagerRef.HasComponent(component_type, self.mEntityID);
}
pub fn GetUUID(self: Entity) u128 {
    return self.mECSManagerRef.GetComponent(IDComponent, self.mEntityID).*.ID;
}
pub fn GetName(self: Entity) []const u8 {
    return &self.mECSManagerRef.GetComponent(NameComponent, self.mEntityID).*.Name;
}
pub fn Duplicate(self: Entity) !Entity {
    return try self.mECSManagerRef.DuplicateEntity(self.mEntityID);
}

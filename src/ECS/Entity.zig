
const ECSManager = @import("ECSManager.zig");
const Components = @import("Components.zig");
const IDComponent = Components.IDComponent;
const NameComponent = Components.NameComponent;
const Entity = @This();


mEntityID: u32,
mECSManager: *ECSManager,

pub fn AddComponent(self: Entity, comptime component_type: type, component: component_type) !*component_type {
    return try self.mECSManager.AddComponent(component_type, self.mEntityID, component);
}
pub fn RemoveComponent(self: Entity, comptime component_type: type) !void {
    try self.mECSManager.RemoveComponent(component_type, self.mEntityID);
}
pub fn GetComponent(self: Entity, comptime component_type: type) *component_type {
    return self.mECSManager.GetComponent(component_type, self.mEntityID);
}
pub fn HasComponent(self: Entity, comptime component_type: type) bool {
    return self.mECSManager.HasComponent(component_type, self.mEntityID);
}
pub fn GetUUID(self: Entity) IDComponent {
    return self.mECSManager.GetComponent(IDComponent, self.mEntityID);
}
pub fn GetName(self: Entity) NameComponent {
    return self.mECSManager.GetComponent(NameComponent, self.mEntityID);
}
pub fn Duplicate(self: Entity) !Entity {
    return try self.mECSManager.DuplicateEntity(self.mEntityID);
}
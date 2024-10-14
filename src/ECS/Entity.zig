const SceneLayer = @import("../Scene/SceneLayer.zig");
const LayerType = @import("Components/SceneIDComponent.zig").ELayerType;
const Entity = @This();

const Components = @import("Components.zig");
const IDComponent = Components.IDComponent;
const NameComponent = Components.NameComponent;

mEntityID: u32,
mLayer: *SceneLayer,

pub fn AddComponent(self: Entity, comptime component_type: type, component: component_type) !*component_type {
    return try self.mLayer.mECSManager.AddComponent(component_type, self.mEntityID, component);
}
pub fn RemoveComponent(self: Entity, comptime component_type: type) !void {
    try self.mLayer.mECSManager.RemoveComponent(component_type, self.mEntityID);
}
pub fn GetComponent(self: Entity, comptime component_type: type) *component_type {
    return self.mLayer.mECSManager.GetComponent(component_type, self.mEntityID);
}
pub fn HasComponent(self: Entity, comptime component_type: type) bool {
    return self.mLayer.mECSManager.HasComponent(component_type, self.mEntityID);
}
pub fn GetUUID(self: Entity) IDComponent {
    return self.mLayer.mECSManager.GetComponent(IDComponent, self.mEntityID);
}
pub fn GetName(self: Entity) NameComponent {
    return self.mLayer.mECSManager.GetComponent(NameComponent, self.mEntityID);
}

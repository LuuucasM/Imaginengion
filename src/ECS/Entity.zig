const std = @import("std");
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
pub fn GetUUID(self: Entity) u128 {
    return self.mECSManager.GetComponent(IDComponent, self.mEntityID).*.ID;
}
pub fn GetName(self: Entity) []const u8 {
    return &self.mECSManager.GetComponent(NameComponent, self.mEntityID).*.Name;
}
pub fn Duplicate(self: Entity) !Entity {
    return try self.mECSManager.DuplicateEntity(self.mEntityID);
}

pub fn Stringify(self: Entity, out: *std.ArrayList(u8)) !void {
    try self.mECSManager.Stringify(out, self.mEntityID);
}

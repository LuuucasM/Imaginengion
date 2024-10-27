const std = @import("std");
const SceneLayer = @import("../Scene/SceneLayer.zig");
const Components = @import("Components.zig");
const EComponents = Components.EComponents;
const IDComponent = Components.IDComponent;
const NameComponent = Components.NameComponent;
const Entity = @This();
pub const NullEntity: u32 = ~0;

mEntityID: u32,
mSceneLayerRef: *const SceneLayer,

pub fn AddComponent(self: Entity, comptime component_type: type, component: component_type) !*component_type {
    return try self.mSceneLayerRef.mECSManagerRef.AddComponent(component_type, self.mEntityID, component);
}
pub fn RemoveComponent(self: Entity, comptime component_type: type) !void {
    try self.mSceneLayerRef.mECSManagerRef.RemoveComponent(component_type, self.mEntityID);
}
pub fn GetComponent(self: Entity, comptime component_type: type) *component_type {
    return self.mSceneLayerRef.mECSManagerRef.GetComponent(component_type, self.mEntityID);
}
pub fn HasComponent(self: Entity, comptime component_type: type) bool {
    return self.mSceneLayerRef.mECSManagerRef.HasComponent(component_type, self.mEntityID);
}
pub fn GetUUID(self: Entity) u128 {
    return self.mSceneLayerRef.mECSManagerRef.GetComponent(IDComponent, self.mEntityID).*.ID;
}
pub fn GetName(self: Entity) []const u8 {
    return &self.mSceneLayerRef.mECSManagerRef.GetComponent(NameComponent, self.mEntityID).*.Name;
}
pub fn Duplicate(self: Entity) !Entity {
    return try self.mSceneLayerRef.mECSManagerRef.DuplicateEntity(self.mEntityID);
}

pub fn Stringify(self: Entity, write_stream: *std.json.WriteStream(std.ArrayList(u8).Writer, .{ .checked_to_fixed_depth = 256 })) !void {
    try self.mSceneLayerRef.mECSManagerRef.Stringify(write_stream, self.mEntityID);
}

pub fn DeStringify(self: Entity, component_index: usize, component_string: []const u8) !void {
    try self.mSceneLayerRef.mECSManagerRef.DeStringify(component_index, component_string, self.mEntityID);
}

pub fn EntityImguiRender(self: Entity){
    self.mSceneLayerRef.mECSManagerRef.EntityImguiRender(self.mEntityID);
}
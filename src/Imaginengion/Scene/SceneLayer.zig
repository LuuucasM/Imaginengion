const std = @import("std");
const ECSManagerScenes = @import("SceneManager.zig").ECSManagerScenes;
const ECSManagerGameObj = @import("SceneManager.zig").ECSManagerGameObj;
const SceneComponents = @import("SceneComponents.zig");
const EntityComponents = @import("../GameObjects/Components.zig");
const SceneIDComponent = SceneComponents.IDComponent;
const EntityIDComponent = EntityComponents.IDComponent;
const EntityNameComponent = EntityComponents.NameComponent;
const EntitySceneComponent = EntityComponents.SceneIDComponent;
const TransformComponent = EntityComponents.TransformComponent;
const SceneType = @import("../Scene/SceneManager.zig").SceneType;
const Entity = @import("../GameObjects/Entity.zig");
const GenUUID = @import("../Core/UUID.zig").GenUUID;

pub const NullEntity: SceneType = ~0;
const SceneLayer = @This();

mSceneID: SceneType,
mECSManagerGORef: *ECSManagerGameObj,
mECSManagerSCRef: *ECSManagerScenes,

//for the scenes themselves
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
    return self.mECSManagerSCRef.GetComponent(SceneIDComponent, self.mSceneID).*.ID;
}
pub fn Duplicate(self: SceneLayer) !SceneLayer {
    return try self.mECSManagerSCRef.DuplicateEntity(self.mSceneID);
}

//for the entities in the scenes
pub fn CreateBlankEntity(self: SceneLayer) !Entity {
    const new_entity = Entity{ .mEntityID = try self.mECSManagerGORef.CreateEntity(), .mECSManagerRef = self.mECSManagerGORef };
    _ = try new_entity.AddComponent(EntitySceneComponent, .{ .SceneID = self.mSceneID });

    return new_entity;
}

pub fn CreateEntity(self: SceneLayer) !Entity {
    return self.CreateEntityWithUUID(try GenUUID());
}

pub fn CreateEntityWithUUID(self: SceneLayer, uuid: u128) !Entity {
    const e = Entity{ .mEntityID = try self.mECSManagerGORef.CreateEntity(), .mECSManagerRef = self.mECSManagerGORef };
    _ = try e.AddComponent(EntityIDComponent, .{ .ID = uuid });
    _ = try e.AddComponent(EntitySceneComponent, .{ .SceneID = self.mSceneID });
    var name = [_]u8{0} ** 24;
    @memcpy(name[0..14], "Unnamed Entity");
    _ = try e.AddComponent(EntityNameComponent, .{ .Name = name });
    _ = try e.AddComponent(TransformComponent, null);

    return e;
}

pub fn DestroyEntity(self: SceneLayer, e: Entity) !void {
    try self.mECSManagerGORef.DestroyEntity(e.mEntityID);
}

pub fn DuplicateEntity(self: SceneLayer, original_entity: Entity) !Entity {
    const new_entity = Entity{ .mEntityID = try self.mECSManagerGORef.DuplicateEntity(original_entity.mEntityID), .mSceneLayerRef = self.mECSManagerGORef };
    return new_entity;
}

const std = @import("std");
const ECSManagerScenes = @import("SceneManager.zig").ECSManagerScenes;
const ECSManagerGameObj = @import("SceneManager.zig").ECSManagerGameObj;
const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;
const SceneComponents = @import("SceneComponents.zig");
const EntityComponents = @import("../GameObjects/Components.zig");
const SceneIDComponent = SceneComponents.IDComponent;
const SceneScriptComponent = SceneComponents.ScriptComponent;
const EntityIDComponent = EntityComponents.IDComponent;
const EntityNameComponent = EntityComponents.NameComponent;
const EntitySceneComponent = EntityComponents.SceneIDComponent;
const TransformComponent = EntityComponents.TransformComponent;
const EntityScriptComponent = EntityComponents.ScriptComponent;
const Entity = @import("../GameObjects/Entity.zig");
const GenUUID = @import("../Core/UUID.zig").GenUUID;
const GameEventManager = @import("../Events/GameEventManager.zig");
const ImguiEventManager = @import("../Events/ImguiEventManager.zig");

pub const Type = u32;
pub const NullScene: Type = std.math.maxInt(Type);
const SceneLayer = @This();

mSceneID: Type,
mECSManagerGORef: *ECSManagerGameObj,
mECSManagerSCRef: *ECSManagerScenes,

//for the scenes themselves
pub fn AddComponent(self: SceneLayer, comptime component_type: type, component: ?component_type) !*component_type {
    return try self.mECSManagerSCRef.AddComponent(component_type, self.mSceneID, component);
}
pub fn RemoveComponent(self: SceneLayer, comptime component_type: type) !void {
    try self.mECSManagerSCRef.RemoveComponent(component_type, self.mSceneID);
}
pub fn GetComponent(self: SceneLayer, comptime component_type: type) ?*component_type {
    return self.mECSManagerSCRef.GetComponent(component_type, self.mSceneID);
}
pub fn HasComponent(self: SceneLayer, comptime component_type: type) bool {
    return self.mECSManagerSCRef.HasComponent(component_type, self.mSceneID);
}
pub fn GetEntityGroup(self: SceneLayer, comptime query: GroupQuery, allocator: std.mem.Allocator) !std.ArrayList(Entity.Type) {
    var entity_list = try self.mECSManagerGORef.GetGroup(query, allocator);
    self.FilterEntityByScene(&entity_list, allocator);
    return entity_list;
}
pub fn GetUUID(self: SceneLayer) u128 {
    return self.mECSManagerSCRef.GetComponent(SceneIDComponent, self.mSceneID).?.*.ID;
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

pub fn CreateEntityWithUUID(self: SceneLayer, uuid: u64) !Entity {
    const e = Entity{ .mEntityID = try self.mECSManagerGORef.CreateEntity(), .mECSManagerRef = self.mECSManagerGORef };
    _ = try e.AddComponent(EntityIDComponent, .{ .ID = uuid });
    _ = try e.AddComponent(EntitySceneComponent, .{ .SceneID = self.mSceneID });
    var name = [_]u8{0} ** 24;
    @memcpy(name[0..14], "Unnamed Entity");
    _ = try e.AddComponent(EntityNameComponent, .{ .Name = name });
    _ = try e.AddComponent(TransformComponent, null);

    return e;
}

pub fn Delete(self: SceneLayer) !void {
    try GameEventManager.Insert(.{ .ET_DestroySceneEvent = .{ .mSceneID = self.mSceneID } });
    try ImguiEventManager.Insert(.{ .ET_DeleteSceneEvent = .{ .mScene = self } });
}

pub fn DuplicateEntity(self: SceneLayer, original_entity: Entity) !Entity {
    const new_entity = Entity{ .mEntityID = try self.mECSManagerGORef.DuplicateEntity(original_entity.mEntityID), .mSceneLayerRef = self.mECSManagerGORef };
    return new_entity;
}

pub fn FilterEntityByScene(self: SceneLayer, entity_result_list: *std.ArrayList(Entity.Type), list_allocator: std.mem.Allocator) void {
    if (entity_result_list.items.len == 0) return;

    var end_index: usize = entity_result_list.items.len;
    var i: usize = 0;

    while (i < end_index) {
        const entity_scene_component = self.mECSManagerGORef.GetComponent(EntitySceneComponent, entity_result_list.items[i]).?;
        if (entity_scene_component.SceneID != self.mSceneID) {
            entity_result_list.items[i] = entity_result_list.items[end_index - 1];
            end_index -= 1;
        } else {
            i += 1;
        }
    }

    entity_result_list.shrinkAndFree(list_allocator, end_index);
}

pub fn FilterEntityScriptsByScene(self: SceneLayer, scripts_result_list: *std.ArrayList(Entity.Type), list_allocator: std.mem.Allocator) void {
    if (scripts_result_list.items.len == 0) return;

    var end_index: usize = scripts_result_list.items.len;
    var i: usize = 0;

    while (i < end_index) {
        const entity_script_component = self.mECSManagerGORef.GetComponent(EntityScriptComponent, scripts_result_list.items[i]).?;
        const parent_scene_component = self.mECSManagerGORef.GetComponent(EntitySceneComponent, entity_script_component.mParent).?;
        if (parent_scene_component.SceneID != self.mSceneID) {
            scripts_result_list.items[i] = scripts_result_list.items[end_index - 1];
            end_index -= 1;
        } else {
            i += 1;
        }
    }

    scripts_result_list.shrinkAndFree(list_allocator, end_index);
}

pub fn FilterSceneScriptsByScene(self: SceneLayer, scripts_result_list: *std.ArrayList(Entity.Type), list_allocator: std.mem.Allocator) void {
    if (scripts_result_list.items.len == 0) return;

    var end_index: usize = scripts_result_list.items.len;
    var i: usize = 0;

    while (i < end_index) {
        const scene_script_component = self.mECSManagerSCRef.GetComponent(SceneScriptComponent, scripts_result_list.items[i]).?;
        if (scene_script_component.mParent != self.mSceneID) {
            scripts_result_list.items[i] = scripts_result_list.items[end_index - 1];
            end_index -= 1;
        } else {
            i += 1;
        }
    }

    scripts_result_list.shrinkAndFree(list_allocator, end_index);
}

pub fn EntityListDifference(self: SceneLayer, result: *std.ArrayList(Entity.Type), list2: std.ArrayList(Entity.Type), allocator: std.mem.Allocator) !void {
    try self.mECSManagerGORef.EntityListDifference(result, list2, allocator);
}

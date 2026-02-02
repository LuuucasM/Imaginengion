const std = @import("std");
const ECSManagerScenes = @import("SceneManager.zig").ECSManagerScenes;
const ECSManagerGameObj = @import("SceneManager.zig").ECSManagerGameObj;
const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;
const SceneComponents = @import("SceneComponents.zig");
const EntityComponents = @import("../GameObjects/Components.zig");
const SceneUUIDComponent = SceneComponents.UUIDComponent;
const SceneScriptComponent = SceneComponents.ScriptComponent;
const SceneComponent = SceneComponents.SceneComponent;
const SceneNameComponent = SceneComponents.NameComponent;
const EntityUUIDComponent = EntityComponents.UUIDComponent;
const EntityNameComponent = EntityComponents.NameComponent;
const EntitySceneComponent = EntityComponents.EntitySceneComponent;
const TransformComponent = EntityComponents.TransformComponent;
const EntityScriptComponent = EntityComponents.ScriptComponent;
const Entity = @import("../GameObjects/Entity.zig");
const GenUUID = @import("../Core/UUID.zig").GenUUID;
const EngineContext = @import("../Core/EngineContext.zig");
const ChildType = @import("../ECS/ECSManager.zig").ChildType;
const SceneChildComponent = @import("../ECS/Components.zig").ChildComponent(SceneLayer.Type);

pub const Type = u32;
pub const NullScene: Type = std.math.maxInt(Type);
const SceneLayer = @This();

mSceneID: Type = NullScene,
mECSManagerGORef: *ECSManagerGameObj = undefined,
mECSManagerSCRef: *ECSManagerScenes = undefined,

//for the scenes themselves
pub fn AddComponent(self: SceneLayer, new_component: anytype) !*@typeInfo(new_component) {
    return try self.mECSManagerSCRef.AddComponent(self.mSceneID, new_component);
}
pub fn RemoveComponent(self: SceneLayer, engine_allocator: std.mem.Allocator, comptime component_type: type) !void {
    try self.mECSManagerSCRef.RemoveComponent(engine_allocator, component_type, self.mSceneID);
}
pub fn GetComponent(self: SceneLayer, comptime component_type: type) ?*component_type {
    return self.mECSManagerSCRef.GetComponent(component_type, self.mSceneID);
}
pub fn HasComponent(self: SceneLayer, comptime component_type: type) bool {
    return self.mECSManagerSCRef.HasComponent(component_type, self.mSceneID);
}
pub fn GetEntityGroup(self: SceneLayer, frame_allocator: std.mem.Allocator, comptime query: GroupQuery) !std.ArrayList(Entity.Type) {
    var entity_list = try self.mECSManagerGORef.GetGroup(frame_allocator, query);
    self.FilterEntityByScene(frame_allocator, &entity_list);
    return entity_list;
}
pub fn GetUUID(self: SceneLayer) u128 {
    return self.mECSManagerSCRef.GetComponent(SceneUUIDComponent, self.mSceneID).?.*.ID;
}
pub fn Duplicate(self: SceneLayer) !SceneLayer {
    return try self.mECSManagerSCRef.DuplicateEntity(self.mSceneID);
}

pub fn AddBlankChild(self: SceneLayer, child_type: ChildType) !SceneLayer {
    return SceneLayer{
        .mSceneID = try self.mECSManagerSCRef.AddChild(self.mSceneID, child_type),
        .mECSManagerGORef = self.mECSManagerGORef,
        .mECSManagerSCRef = self.mECSManagerSCRef,
    };
}

pub fn AddChild(self: SceneLayer, engine_context: *EngineContext, child_type: ChildType) !SceneLayer {
    const child_scene = SceneLayer{
        .mSceneID = try self.mECSManagerSCRef.AddChild(self.mSceneID, child_type),
        .mECSManagerGORef = self.mECSManagerGORef,
        .mECSManagerSCRef = self.mECSManagerSCRef,
    };

    _ = try child_scene.AddComponent(SceneComponent{});
    _ = try child_scene.AddComponent(SceneUUIDComponent{ .ID = try GenUUID() });
    const scene_name_component = try child_scene.AddComponent(SceneNameComponent{ .mAllocator = engine_context.EngineAllocator() });
    _ = try scene_name_component.mName.writer(scene_name_component.mAllocator).write("New Scene");

    return child_scene;
}

//for the entities in the scenes
pub fn CreateBlankEntity(self: *SceneLayer) !Entity {
    const new_entity = Entity{ .mEntityID = try self.mECSManagerGORef.CreateEntity(), .mECSManagerRef = self.mECSManagerGORef };
    _ = try new_entity.AddComponent(EntitySceneComponent{ .mScene = self });

    return new_entity;
}

pub fn CreateEntity(self: SceneLayer, engine_allocator: std.mem.Allocator) !Entity {
    return self.CreateEntityWithUUID(engine_allocator, try GenUUID());
}

pub fn CreateEntityWithUUID(self: *SceneLayer, engine_allocator: std.mem.Allocator, uuid: u64) !Entity {
    var e = Entity{ .mEntityID = try self.mECSManagerGORef.CreateEntity(), .mECSManagerRef = self.mECSManagerGORef };
    _ = try e.AddComponent(EntityUUIDComponent{ .ID = uuid });
    _ = try e.AddComponent(EntitySceneComponent{ .mScene = self });

    const new_name_component = try e.AddComponent(EntityNameComponent{ .mAllocator = engine_allocator });
    _ = try new_name_component.mName.writer(new_name_component.mAllocator).write("New Entity");

    _ = try e.AddComponent(TransformComponent{});
    e._CalculateWorldTransform();

    return e;
}

pub fn Delete(self: SceneLayer, engine_context: *EngineContext) !void {
    try engine_context.mGameEventManager.Insert(engine_context.EngineAllocator(), .{ .ET_DestroySceneEvent = .{ .mSceneID = self.mSceneID } });
    try engine_context.mImguiEventManager.Insert(engine_context.EngineAllocator(), .{ .ET_DeleteSceneEvent = .{ .mScene = self } });
}

pub fn AddBlankChildEntity(_: SceneLayer, parent_entity: Entity, child_type: ChildType) !Entity {
    return parent_entity.AddBlankChild(child_type);
}

pub fn AddChildEntity(_: SceneLayer, engine_allocator: std.mem.Allocator, parent_entity: Entity, child_type: ChildType) !Entity {
    return try parent_entity.AddChild(engine_allocator, child_type);
}

pub fn DuplicateEntity(_: SceneLayer, original_entity: Entity) !Entity {
    return original_entity.Duplicate();
}

pub fn FilterEntityByScene(self: SceneLayer, list_allocator: std.mem.Allocator, entity_result_list: *std.ArrayList(Entity.Type)) void {
    if (entity_result_list.items.len == 0) return;

    var end_index: usize = entity_result_list.items.len;
    var i: usize = 0;

    while (i < end_index) {
        const script_entity = Entity{ .mEntityID = entity_result_list.items[i], .mECSManagerRef = self.mECSManagerGORef };
        const scene_component = script_entity.GetComponent(EntitySceneComponent).?;

        if (scene_component.mScene.mSceneID != self.mSceneID) {
            entity_result_list.items[i] = entity_result_list.items[end_index - 1];
            end_index -= 1;
        } else {
            i += 1;
        }
    }

    entity_result_list.shrinkAndFree(list_allocator, end_index);
}

pub fn FilterSceneScriptsByScene(self: SceneLayer, list_allocator: std.mem.Allocator, scripts_result_list: *std.ArrayList(Entity.Type)) void {
    if (scripts_result_list.items.len == 0) return;

    var end_index: usize = scripts_result_list.items.len;
    var i: usize = 0;

    while (i < end_index) {
        const script_scene_layer = SceneLayer{ .mSceneID = scripts_result_list.items[i], .mECSManagerGORef = self.mECSManagerGORef, .mECSManagerSCRef = self.mECSManagerSCRef };
        std.debug.assert(script_scene_layer.HasComponent(SceneChildComponent));

        const script_scene_component = script_scene_layer.GetComponent(SceneChildComponent).?;
        if (script_scene_component.mParent != self.mSceneID) {
            scripts_result_list.items[i] = scripts_result_list.items[end_index - 1];
            end_index -= 1;
        } else {
            i += 1;
        }
    }

    scripts_result_list.shrinkAndFree(list_allocator, end_index);
}

pub fn EntityListDifference(self: SceneLayer, allocator: std.mem.Allocator, result: *std.ArrayList(Entity.Type), list2: std.ArrayList(Entity.Type)) !void {
    try self.mECSManagerGORef.EntityListDifference(result, list2, allocator);
}

pub fn GetEntityECSAllocator(self: SceneLayer) std.mem.Allocator {
    return self.mECSManagerGORef.GetECSAllocator();
}

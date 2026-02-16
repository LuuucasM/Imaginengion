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
const PathType = @import("../Assets/Assets/FileMetaData.zig").PathType;
const Assets = @import("../Assets/Assets.zig");
const ScriptAsset = Assets.ScriptAsset;
const SceneManager = @import("SceneManager.zig");
const OnSceneStartScript = SceneComponents.OnSceneStartScript;
const NewEntityConfig = Entity.NewEntityConfig;

pub const NewSceneConfig = struct {
    bAddSceneUUID: bool = true,
    bAddSceneName: bool = true,
};

pub const Type = u32;
pub const NullScene: Type = std.math.maxInt(Type);
const SceneLayer = @This();

mSceneID: Type = NullScene,
mSceneManager: *SceneManager = undefined,

//===================for the scenes==============================================
pub fn AddComponent(self: SceneLayer, new_component: anytype) !*@TypeOf(new_component) {
    return try self.mSceneManager.mECSManagerSC.AddComponent(self.mSceneID, new_component);
}
pub fn RemoveComponent(self: SceneLayer, engine_allocator: std.mem.Allocator, comptime component_type: type) !void {
    try self.mSceneManager.mECSManagerSC.RemoveComponent(engine_allocator, component_type, self.mSceneID);
}
pub fn GetComponent(self: SceneLayer, comptime component_type: type) ?*component_type {
    return self.mSceneManager.mECSManagerSC.GetComponent(component_type, self.mSceneID);
}
pub fn HasComponent(self: SceneLayer, comptime component_type: type) bool {
    return self.mSceneManager.mECSManagerSC.HasComponent(component_type, self.mSceneID);
}

pub fn GetUUID(self: SceneLayer) u128 {
    return self.mSceneManager.mECSManagerSC.GetComponent(SceneUUIDComponent, self.mSceneID).?.*.ID;
}

pub fn Delete(self: SceneLayer, engine_context: *EngineContext) !void {
    self.mSceneManager.mECSManagerSC.DestroyEntity(engine_context.EngineAllocator(), self.mSceneID);
}

pub fn GetSceneGroup(self: SceneLayer, frame_allocator: std.mem.Allocator, query: GroupQuery) !std.ArrayList(SceneLayer.Type) {
    var scene_list = try self.mSceneManager.mECSManagerSC.GetGroup(frame_allocator, query);
    self.FilterSceneByScene(frame_allocator, &scene_list);
}

pub fn Duplicate(self: *SceneLayer) !SceneLayer {
    return try self.mSceneManager.mECSManagerSC.DuplicateEntity(self.mSceneID);
}

pub fn AddChild(self: *SceneLayer, engine_allocator: std.mem.Allocator, child_type: ChildType, new_scene_config: NewSceneConfig) !SceneLayer {
    const child_scene = SceneLayer{ .mSceneID = self.mSceneManager.mECSManagerSC.AddChild(self.mSceneID, child_type), .mSceneManager = self };
    self.CreateSceneConfig(engine_allocator, child_scene, new_scene_config);
    return child_scene;
}

pub fn CreateSceneConfig(self: *SceneLayer, engine_allocator: std.mem.Allocator, scene_layer: SceneLayer, config: NewSceneConfig) !void {
    if (config.bAddSceneUUID) {
        const uuid_component = SceneUUIDComponent{ .ID = GenUUID() };
        _ = try scene_layer.AddComponent(uuid_component);
        self.mSceneUUIDToWorldID.put(engine_allocator, uuid_component.ID, scene_layer.mSceneID);
    }
    if (config.bAddSceneName) {
        const scene_name_component = SceneNameComponent{
            .mAllocator = engine_allocator,
        };
        scene_name_component.mName.writer(scene_name_component.mAllocator).write("New Scene");

        scene_layer.AddComponent(scene_name_component);
    }
}

pub fn AddComponentScript(self: *SceneLayer, engine_context: *EngineContext, script_asset_path: []const u8, path_type: PathType) !void {
    var new_script_handle = try engine_context.mAssetManager.GetAssetHandleRef(engine_context.EngineAllocator(), script_asset_path, path_type);
    const script_asset = try new_script_handle.GetAsset(engine_context, ScriptAsset);

    std.debug.assert(script_asset.mScriptType == .SceneSceneStart);

    const new_script_component = SceneScriptComponent{
        .mScriptAssetHandle = new_script_handle,
    };

    const new_script_entity = try self.AddChild(engine_context, .Script);

    _ = try new_script_entity.AddComponent(new_script_component);

    _ = switch (script_asset.mScriptType) {
        .SceneSceneStart => try new_script_entity.AddComponent(OnSceneStartScript{}),
        else => @panic("This shouldnt happen!"),
    };
}

fn FilterSceneByScene(self: SceneLayer, list_allocator: std.mem.Allocator, scene_result_list: *std.ArrayList(SceneLayer.Type)) void {
    if (scene_result_list.items.len == 0) return;

    var end_index: usize = scene_result_list.items.len;
    var i: usize = 0;

    while (i < end_index) {
        const script_scene = SceneLayer{ .mEntityID = scene_result_list.items[i], .mSceneManager = self.mSceneManager };
        const child_component = script_scene.GetComponent(SceneChildComponent).?;

        if (child_component.mParent != self.mSceneID) {
            scene_result_list.items[i] = scene_result_list.items[end_index - 1];
            end_index -= 1;
        } else {
            i += 1;
        }
    }

    scene_result_list.shrinkAndFree(list_allocator, end_index);
}

//===================END for the scenes==============================================

//======================for the entities in the scenes=====================================
pub fn CreateEntity(self: SceneLayer, engine_allocator: std.mem.Allocator, new_entity_config: NewEntityConfig) !Entity {
    var new_entity = Entity{ .mEntityID = try self.mSceneManager.mECSManagerGO.CreateEntity(), .mECSManagerRef = self.mSceneManager.mECSManagerGO };
    new_entity.CreateEntityConfig(engine_allocator, new_entity_config);
    new_entity.AddComponent(EntitySceneComponent{ .mScene = self });
    return new_entity;
}

pub fn CreateChildEntity(self: SceneLayer, engine_allocator: std.mem.Allocator, parent_entity: Entity, child_type: ChildType, new_entity_config: NewEntityConfig) !Entity {
    const child_entity = try parent_entity.AddChild(engine_allocator, child_type, new_entity_config);
    child_entity.CreateEntityConfig(engine_allocator, new_entity_config);
    child_entity.AddComponent(EntitySceneComponent{ .mScene = self });
    return child_entity;
}

pub fn GetEntity(self: SceneLayer, entity_id: Entity.Type) Entity {
    return Entity{ .mEntityID = entity_id, .mECSManagerRef = self.mSceneManager.mECSManagerGO };
}

pub fn GetEntityGroup(self: SceneLayer, frame_allocator: std.mem.Allocator, comptime query: GroupQuery) !std.ArrayList(Entity.Type) {
    var entity_list = try self.mSceneManager.mECSManagerGO.GetGroup(frame_allocator, query);
    self.FilterEntityByScene(frame_allocator, &entity_list);
    return entity_list;
}

fn FilterEntityByScene(self: SceneLayer, list_allocator: std.mem.Allocator, entity_result_list: *std.ArrayList(Entity.Type)) void {
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
//======================for the entities in the scenes=====================================

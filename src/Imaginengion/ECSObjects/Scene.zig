const std = @import("std");
const SceneManager = @import("../Scene/SceneManager.zig");

const ECSManagerScenes = SceneManager.ECSManagerScenes;
const ECSManagerEntities = SceneManager.ECSManagerEntities;
const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;
const SceneComponents = @import("../ECSComponents/SComponents.zig");
const EntityComponents = @import("../ECSComponents/EComponents.zig");
const SceneUUIDComponent = SceneComponents.UUIDComponent;
const SceneScriptComponent = SceneComponents.ScriptComponent;
const SceneComponent = SceneComponents.SceneComponent;
const SceneNameComponent = SceneComponents.NameComponent;
const EntityUUIDComponent = EntityComponents.UUIDComponent;
const EntityNameComponent = EntityComponents.NameComponent;
const EntitySceneComponent = EntityComponents.EntitySceneComponent;
const TransformComponent = EntityComponents.TransformComponent;
const EntityScriptComponent = EntityComponents.ScriptComponent;
const Entity = @import("Entity.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const ChildType = @import("../ECS/ECSManager.zig").ChildType;
const SceneParentComponent = @import("../ECS/Components.zig").ParentComponent(Type);
const SceneChildComponent = @import("../ECS/Components.zig").ChildComponent(Type);
const PathType = @import("../Assets/AssetManager.zig").PathType;
const Assets = @import("../ECSComponents/AComponents.zig");
const ScriptAsset = Assets.ScriptAsset;
const OnSceneStartScript = SceneComponents.OnSceneStartScript;
const SceneInputPressed = SceneComponents.InputPressedScript;
const SceneOnUpdate = SceneComponents.OnUpdateScript;
const NewEntityConfig = Entity.NewEntityConfig;
const ECSCore = @import("ECSObject.zig").Core;
const WorldManager = @import("../Core/WorldManager.zig");
const AssetHandle = @import("AssetHandle.zig");

const Core = ECSCore(Scene);

pub const NewSceneConfig = struct {
    bAddSceneUUID: bool = true,
    bAddSceneName: bool = true,
};

pub const Type = u32;
pub const NullObject: Type = std.math.maxInt(Type);
const Scene = @This();

const uninit: Scene = .{
    .mID = NullObject,
    .mManager = undefined,
};

mID: Type,
mManager: *WorldManager,

//===================for the scenes==============================================
pub const AddComponent = Core.AddComponent;

pub const RemoveComponent = Core.RemoveComponent;

pub const GetComponent = Core.GetComponent;

pub const HasComponent = Core.HasComponent;

pub const GetUUID = Core.GetUUID;

pub const GetName = Core.GetName;

pub const Delete = Core.Delete;

pub const Duplicate = Core.Duplicate;

//TODO: move to SManager
//pub fn CreateSceneConfig(self: *Scene, engine_context: *EngineContext, config: NewSceneConfig) !void {
//    if (config.bAddSceneUUID) {
//        const io_source = std.Random.IoSource{ .io = engine_context.Io() };
//        const new_random = io_source.interface();
//        const uuid_component = SceneUUIDComponent{ .ID = new_random.int(u64) };
//        _ = try self.AddComponent(engine_context, uuid_component);
//        try self.mSceneManager.AddUUID(engine_context.EngineAllocator(), uuid_component.ID, self.mSceneID);
//    }
//    if (config.bAddSceneName) {
//        var scene_name_component: SceneNameComponent = .empty;
//        _ = try scene_name_component.mName.print(engine_context.EngineAllocator(), "New Scene", .{});
//
//        _ = try self.AddComponent(engine_context, scene_name_component);
//    }
//}

pub fn AddScript(self: Scene, engine_context: *EngineContext, new_script_handle: AssetHandle) !void {
    const script_asset = try new_script_handle.GetAsset(engine_context, ScriptAsset);
    const script_type = script_asset.GetScriptType();
    _ValidateScriptType(script_type);

    const new_script_entity = try Core.AddScript(self, engine_context, new_script_handle);

    _ = switch (script_asset.GetScriptType()) {
        .SceneSceneStart => try new_script_entity.AddComponent(engine_context, OnSceneStartScript{}),
        .SceneInputPressed => try new_script_entity.AddComponent(engine_context, SceneInputPressed{}),
        .SceneOnUpdate => try new_script_entity.AddComponent(engine_context, SceneOnUpdate{}),
        else => unreachable,
    };
}

pub const IsActive = Core.IsActive;
pub const Invalidate = Core.Invalidate;
pub const IsIDValid = Core.IsIDValid;
//===================END for the scenes==============================================

//======================for the entities in the scenes=====================================

pub fn CreateEntity(self: Scene, engine_context: *EngineContext, new_entity_config: NewEntityConfig) !Entity {
    var new_entity = try self.mManager.mEManager.CreateEntity(engine_context.EngineAllocator(), new_entity_config);
    _ = try new_entity.AddComponent(engine_context, EntitySceneComponent{ .mScene = self });
    return new_entity;
}

pub fn GetEntity(self: Scene, entity_id: Entity.Type) Entity {
    return Entity{ .mID = entity_id, .mManager = self.mManager };
}

pub fn GetEntityGroup(self: Scene, frame_allocator: std.mem.Allocator, comptime query: GroupQuery) !std.ArrayList(Entity.Type) {
    var entity_list = try self.mManager.mEManager.GetGroup(frame_allocator, query);
    self.FilterEntityByScene(frame_allocator, &entity_list);
    return entity_list;
}

fn FilterEntityByScene(self: Scene, list_allocator: std.mem.Allocator, entity_result_list: *std.ArrayList(Entity.Type)) void {
    if (entity_result_list.items.len == 0) return;

    var end_index: usize = entity_result_list.items.len;
    var i: usize = 0;

    while (i < end_index) {
        const script_entity = self.GetEntity(entity_result_list.items[i]);
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

fn _ValidateScriptType(script_type: ScriptAsset.ScriptType) void {
    std.debug.assert(script_type == .SceneInputPressed or
        script_type == .SceneOnUpdate or
        script_type == .SceneSceneStart);
}

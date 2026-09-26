const std = @import("std");
const WorldManager = @import("../Core/WorldManager.zig");

const ECSManagerScenes = WorldManager.ECSManagerScenes;
const ECSManagerEntities = WorldManager.ECSManagerEntities;
const GroupQuery = @import("../ECS/ECSManager.zig").GroupQuery;
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
const PathType = @import("../ECSManagers/AManager.zig").PathType;
const Assets = @import("../ECSComponents/AComponents.zig");
const ScriptAsset = Assets.ScriptAsset;
const OnSceneStartScript = SceneComponents.OnSceneStartScript;
const SceneInputPressed = SceneComponents.InputPressedScript;
const SceneOnUpdate = SceneComponents.OnUpdateScript;
const NewEntityConfig = Entity.CreateConfig;
const ECSCore = @import("ECSObject.zig").Core;
const AssetHandle = @import("AssetHandle.zig");

const Core = ECSCore(Scene);

pub const CreateConfig = struct {
    bAddSceneUUID: bool,
    bAddSceneName: bool,
};

pub const DefaultConfig: CreateConfig = .{
    .bAddSceneName = true,
    .bAddSceneUUID = true,
};

/// Nothing added, for objects whose components all come from somewhere else (e.g. a file)
pub const BlankConfig: CreateConfig = .{
    .bAddSceneName = false,
    .bAddSceneUUID = false,
};

/// A script child (see Core.AddScript): no UUID, nothing looks one up and it is saved as its ScriptComponent alone
pub const ScriptConfig: CreateConfig = .{
    .bAddSceneName = true,
    .bAddSceneUUID = false,
};

pub const Type = u32;
pub const NullObject: Type = std.math.maxInt(Type);
const Scene = @This();

pub const uninit: Scene = .{
    .mID = NullObject,
    .mManager = undefined,
};

mID: Type,
mManager: *WorldManager,

//===================for the scenes==============================================
pub const AddComponent = Core.AddComponent;

pub const RemoveComponent = Core.RemoveComponent;
pub const RemoveComponentSync = Core.RemoveComponentSync;

pub const GetComponent = Core.GetComponent;

pub const HasComponent = Core.HasComponent;

pub const GetUUID = Core.GetUUID;

pub const GetName = Core.GetName;

pub const Delete = Core.Delete;

pub const SetTmpl = Core.SetTmpl;

pub const Fill = Core.Fill;

pub const Strip = Core.Strip;

pub const MakeTmpl = Core.MakeTmpl;

pub const Duplicate = Core.Duplicate;

pub const CreateChild = Core.CreateChild;

pub const GetIterator = Core.GetIterator;

pub fn GetSceneComponent(self: Scene) SceneComponent {
    return self.mManager.mSManager.GetSceneComponent(self.mID);
}

//TODO: move to SManager
//pub fn CreateSceneConfig(self: *Scene, engine_context: *EngineContext, config: NewSceneConfig) !void {
//    if (config.bAddSceneUUID) {
//        const io_source = std.Random.IoSource{ .io = engine_context.Io() };
//        const new_random = io_source.interface();
//        const uuid_component = SceneUUIDComponent{ .ID = new_random.int(u64) };
//        _ = try self.AddComponent(engine_context, uuid_component);
//        try self.mManager.AddUUID(engine_context.EngineAllocator(), uuid_component.ID, self.mID);
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

pub const AddComponentScript = Core.AddComponentScript;

pub const IsActive = Core.IsActive;
pub const Invalidate = Core.Invalidate;
pub const IsIDValid = Core.IsIDValid;
//===================END for the scenes==============================================

//======================for the entities in the scenes=====================================

pub fn CreateEntity(self: Scene, engine_context: *EngineContext, new_entity_config: NewEntityConfig) !Entity {
    var new_entity = try self.mManager.mEManager.CreateEntity(engine_context, new_entity_config);
    _ = try new_entity.AddComponent(engine_context, EntitySceneComponent{ .mScene = self });
    return new_entity;
}

/// Loads an entity file as a new top level entity of this scene. Blank, every component comes from the file
pub fn LoadEntity(self: Scene, engine_context: *EngineContext, abs_path: []const u8) !Entity {
    const new_entity = try self.CreateEntity(engine_context, Entity.BlankConfig);
    try engine_context.mSerializer.DeserializeECSObj(engine_context, new_entity, abs_path, .Text);
    return new_entity;
}

/// A new top level entity that is a copy of the template `tmpl` (a handle to an EntityAsset), with a transform of
/// its own for where it goes. It has no UUID and takes the template's name. See Core.Fill
pub fn Spawn(self: Scene, engine_context: *EngineContext, tmpl: AssetHandle) !Entity {
    const entity = try self.CreateEntity(engine_context, .{ .bAddUUID = false, .bAddName = false, .bAddTransform = true });
    errdefer entity.Delete(engine_context) catch {};
    try entity.SetTmpl(engine_context, tmpl);
    return entity;
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

        if (scene_component.mScene.mID != self.mID) {
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

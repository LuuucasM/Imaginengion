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
const GenUUID = @import("../Serializer/Serializer.zig").GenUUID;
const EngineContext = @import("../Core/EngineContext.zig");
const ChildType = @import("../ECS/ECSManager.zig").ChildType;
const SceneParentComponent = @import("../ECS/Components.zig").ParentComponent(Type);
const SceneChildComponent = @import("../ECS/Components.zig").ChildComponent(Type);
const PathType = @import("../Assets/AssetManager.zig").PathType;
const Assets = @import("../Assets/Assets.zig");
const ScriptAsset = Assets.ScriptAsset;
const SceneManager = @import("SceneManager.zig");
const OnSceneStartScript = SceneComponents.OnSceneStartScript;
const NewEntityConfig = Entity.NewEntityConfig;

pub const NewSceneConfig = struct {
    bAddSceneUUID: bool = true,
    bAddSceneName: bool = true,
};

pub const Iterator = struct {
    pub const IterType = enum {
        Child,
        Script,
    };
    _CurrentScene: SceneLayer,
    _FirstID: Type,
    _IsFirst: bool = true,

    pub fn next(self: *Iterator) ?SceneLayer {
        if (self._IsFirst) {
            @branchHint(.cold);
            self._IsFirst = false;
        } else {
            if (self._CurrentScene.mSceneID == self._FirstID) return null;
        }

        const scene = self._CurrentScene;

        const scene_child_component = scene.GetComponent(SceneChildComponent).?;

        self._CurrentScene = SceneLayer{ .mSceneID = scene_child_component.mNext, .mSceneManager = scene.mSceneManager };

        return scene;
    }
};

pub const Type = u32;
pub const NullScene: Type = std.math.maxInt(Type);
const SceneLayer = @This();

mSceneID: Type = NullScene,
mSceneManager: *SceneManager = undefined,

//===================for the scenes==============================================
pub fn AddComponent(self: SceneLayer, engine_context: *EngineContext, new_component: anytype) !*@TypeOf(new_component) {
    return try self.mSceneManager.mECSManagerSC.AddComponent(engine_context.EngineAllocator(), self.mSceneID, new_component);
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

pub fn GetUUID(self: SceneLayer) u64 {
    return self.mSceneManager.mECSManagerSC.GetComponent(SceneUUIDComponent, self.mSceneID).?.*.ID;
}

pub fn GetName(self: SceneLayer) []const u8 {
    return self.mSceneManager.mECSManagerSC.GetComponent(SceneNameComponent, self.mSceneID).?.*.mName.items;
}

pub fn Delete(self: SceneLayer, engine_context: *EngineContext) !void {
    try self.mSceneManager.mECSManagerSC.DestroyEntity(engine_context.EngineAllocator(), self.mSceneID);
}

pub fn GetSceneGroup(self: SceneLayer, frame_allocator: std.mem.Allocator, query: GroupQuery) !std.ArrayList(SceneLayer.Type) {
    var scene_list = try self.mSceneManager.mECSManagerSC.GetGroup(frame_allocator, query);
    self.FilterSceneByScene(frame_allocator, &scene_list);
}

pub fn Duplicate(self: *SceneLayer) !SceneLayer {
    return try self.mSceneManager.mECSManagerSC.DuplicateEntity(self.mSceneID);
}

pub fn CreateChild(self: SceneLayer, engine_context: *EngineContext, child_type: ChildType, new_scene_config: NewSceneConfig) !SceneLayer {
    var child_scene = SceneLayer{ .mSceneID = try self.mSceneManager.mECSManagerSC.AddChild(engine_context.EngineAllocator(), self.mSceneID, child_type), .mSceneManager = self.mSceneManager };
    try child_scene.CreateSceneConfig(engine_context, new_scene_config);
    return child_scene;
}

pub fn CreateSceneConfig(self: *SceneLayer, engine_context: *EngineContext, config: NewSceneConfig) !void {
    if (config.bAddSceneUUID) {
        const uuid_component = SceneUUIDComponent{ .ID = engine_context.mRandom.int(u64) };
        _ = try self.AddComponent(engine_context, uuid_component);
        try self.mSceneManager.AddUUID(engine_context.EngineAllocator(), uuid_component.ID, self.mSceneID);
    }
    if (config.bAddSceneName) {
        var scene_name_component = SceneNameComponent{ .mAllocator = engine_context.EngineAllocator() };
        _ = try scene_name_component.mName.print(scene_name_component.mAllocator, "New Scene", .{});

        _ = try self.AddComponent(engine_context, scene_name_component);
    }
}

pub fn AddComponentScript(self: SceneLayer, engine_context: *EngineContext, script_asset_path: []const u8, path_type: PathType) !void {
    var new_script_handle = try engine_context.mAssetManager.GetAssetHandleRef(engine_context, .{ .File = .{ .rel_path = script_asset_path, .path_type = path_type } });
    const script_asset = try new_script_handle.GetAsset(engine_context, ScriptAsset);

    const new_script_component = SceneScriptComponent{
        .mScriptAssetHandle = new_script_handle,
    };

    const new_script_entity = try self.CreateChild(engine_context, .Script, .{ .bAddSceneUUID = false });

    _ = try new_script_entity.AddComponent(engine_context, new_script_component);

    _ = switch (script_asset.GetScriptType()) {
        .SceneSceneStart => try new_script_entity.AddComponent(engine_context, OnSceneStartScript{}),
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

pub fn IsActive(self: SceneLayer) bool {
    return self.mSceneManager.mECSManagerSC.IsActiveEntity(self.mSceneID);
}

pub fn GetIterator(self: SceneLayer, comptime iter_type: Iterator.IterType) ?Iterator {
    if (self.GetComponent(SceneParentComponent)) |parent_component| {
        const first = switch (iter_type) {
            .Child => parent_component.mFirstEntity,
            .Script => parent_component.mFirstScript,
        };
        if (first == NullScene) return null;
        return Iterator{
            ._CurrentScene = SceneLayer{ .mSceneID = first, .mSceneManager = self.mSceneManager },
            ._FirstID = first,
        };
    } else {
        return null;
    }
}

//===================END for the scenes==============================================

//======================for the entities in the scenes=====================================
pub fn CreateEntity(self: SceneLayer, engine_context: *EngineContext, new_entity_config: NewEntityConfig) !Entity {
    var new_entity = Entity{ .mEntityID = try self.mSceneManager.mECSManagerGO.CreateEntity(engine_context.EngineAllocator()), .mSceneManager = self.mSceneManager };
    try new_entity.CreateEntityConfig(engine_context, new_entity_config);
    _ = try new_entity.AddComponent(engine_context, EntitySceneComponent{ .mScene = self });
    return new_entity;
}

pub fn CreateChildEntity(self: SceneLayer, engine_allocator: std.mem.Allocator, parent_entity: Entity, child_type: ChildType, new_entity_config: NewEntityConfig) !Entity {
    const child_entity = try parent_entity.CreateChild(child_type);
    try child_entity.CreateEntityConfig(engine_allocator, new_entity_config);
    _ = try child_entity.AddComponent(EntitySceneComponent{ .mScene = self });
    return child_entity;
}

pub fn GetEntity(self: SceneLayer, entity_id: Entity.Type) Entity {
    return Entity{ .mEntityID = entity_id, .mSceneManager = self.mSceneManager };
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

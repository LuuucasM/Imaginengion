const std = @import("std");
const LinAlg = @import("../Math/LinAlg.zig");
const Vec2f32 = LinAlg.Vec2f32;
const Vec3f32 = LinAlg.Vec3f32;
const Mat4f32 = LinAlg.Mat4f32;

const SceneLayer = @import("SceneLayer.zig");
const LayerType = @import("Components/SceneComponent.zig").LayerType;
const SceneSerializer = @import("SceneSerializer.zig");
const PlatformUtils = @import("../PlatformUtils/PlatformUtils.zig");
const GenUUID = @import("../Core/UUID.zig").GenUUID;

const ECSManager = @import("../ECS/ECSManager.zig").ECSManager;
const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;
const Entity = @import("../GameObjects/Entity.zig");

const EntityComponents = @import("../GameObjects/Components.zig");
const EntityComponentsArray = EntityComponents.ComponentsList;
const EEntityComponents = EntityComponents.EComponents;
const EntityTransformComponent = EntityComponents.TransformComponent;
const CameraComponent = EntityComponents.CameraComponent;
const EntityScriptComponent = EntityComponents.ScriptComponent;
const EntitySceneComponent = EntityComponents.SceneIDComponent;
const EntityParentComponent = @import("../ECS/Components.zig").ParentComponent(Entity.Type);
const EntityChildComponent = @import("../ECS/Components.zig").ChildComponent(Entity.Type);
const EntityAISlotComponent = EntityComponents.AISlotComponent;
const EntityIDComponent = EntityComponents.IDComponent;
const EntityNameComponent = EntityComponents.NameComponent;
const EntityPlayerSlotComponent = EntityComponents.PlayerSlotComponent;
const EntityQuadComponent = EntityComponents.QuadComponent;

const SceneComponents = @import("SceneComponents.zig");
const SceneComponentsList = SceneComponents.ComponentsList;
const ESceneComponents = SceneComponents.EComponents;
const SceneComponent = SceneComponents.SceneComponent;
const SceneIDComponent = SceneComponents.IDComponent;
const SceneNameComponent = SceneComponents.NameComponent;
const SceneStackPos = SceneComponents.StackPosComponent;
const SceneTransformComponent = SceneComponents.TransformComponent;
const SceneScriptComponent = SceneComponents.ScriptComponent;

const Assets = @import("../Assets/Assets.zig");
const AssetHandle = @import("../Assets/AssetHandle.zig");
const ScriptAsset = Assets.ScriptAsset;
const SceneAsset = Assets.SceneAsset;
const FileMetaData = Assets.FileMetaData;
const EngineContext = @import("../Core/EngineContext.zig");

const InputPressedEvent = @import("../Events/SystemEvent.zig").InputPressedEvent;

const Tracy = @import("../Core/Tracy.zig");

const SceneManager = @This();

pub const ECSManagerGameObj = ECSManager(Entity.Type, &EntityComponentsArray);

pub const ECSManagerScenes = ECSManager(SceneLayer.Type, &SceneComponentsList);

//scene stuff
mECSManagerGO: ECSManagerGameObj = .{},
mECSManagerSC: ECSManagerScenes = .{},
mGameLayerInsertIndex: usize = 0,
mNumofLayers: usize = 0,

//viewport stuff
mViewportWidth: usize = 0,
mViewportHeight: usize = 0,

pub fn Init(self: *SceneManager, width: usize, height: usize, engine_allocator: std.mem.Allocator) !void {
    try self.mECSManagerGO.Init(engine_allocator);
    try self.mECSManagerSC.Init(engine_allocator);
    self.mViewportWidth = width;
    self.mViewportHeight = height;
}

pub fn Deinit(self: *SceneManager, engine_context: *EngineContext) !void {
    try self.mECSManagerGO.Deinit(engine_context);
    try self.mECSManagerSC.Deinit(engine_context);
}

pub fn CreateEntity(self: *SceneManager, engine_allocator: std.mem.Allocator, scene_id: SceneLayer.Type) !Entity {
    const zone = Tracy.ZoneInit("SceneManager CreateEntity", @src());
    defer zone.Deinit();
    const scene_layer = SceneLayer{ .mSceneID = scene_id, .mECSManagerGORef = &self.mECSManagerGO, .mECSManagerSCRef = &self.mECSManagerSC };
    return scene_layer.CreateEntity(engine_allocator);
}
pub fn CreateEntityWithUUID(self: *SceneManager, engine_allocator: std.mem.Allocator, uuid: u128, scene_id: SceneLayer.Type) !Entity {
    const zone = Tracy.ZoneInit("SceneManager CreateEntityWithUUID", @src());
    defer zone.Deinit();
    const scene_layer = SceneLayer{ .mSceneID = scene_id, .mECSManagerGORef = &self.mECSManagerGO, .mECSManagerSCRef = &self.mECSManagerSC };
    return scene_layer.CreateEntityWithUUID(engine_allocator, uuid);
}

pub fn DestroyEntity(self: *SceneManager, engine_allocator: std.mem.Allocator, destroy_entity: Entity) !void {
    const zone = Tracy.ZoneInit("SceneManager DestroyEntity", @src());
    defer zone.Deinit();

    try self.mECSManagerGO.DestroyEntity(engine_allocator, destroy_entity.mEntityID);
}

pub fn DuplicateEntity(self: *SceneManager, original_entity: Entity, scene_id: SceneLayer.Type) !Entity {
    const zone = Tracy.ZoneInit("SceneManager DuplicateEntity", @src());
    defer zone.Deinit();
    const scene_layer = SceneLayer{ .mSceneID = scene_id, .mECSManagerGORef = &self.mECSManagerGO, .mECSManagerSCRef = &self.mECSManagerSC };
    scene_layer.DuplicateEntity(original_entity);
}

pub fn OnViewportResize(self: *SceneManager, frame_allocator: std.mem.Allocator, viewport_width: usize, viewport_height: usize) !void {
    const zone = Tracy.ZoneInit("SceneManager OnViewportResize", @src());
    defer zone.Deinit();
    self.mViewportWidth = viewport_width;
    self.mViewportHeight = viewport_height;

    const camera_group = try self.mECSManagerGO.GetGroup(frame_allocator, .{ .Component = CameraComponent });
    for (camera_group.items) |entity_id| {
        const entity = Entity{ .mEntityID = entity_id, .mECSManagerRef = &self.mECSManagerGO };
        const camera_component = entity.GetComponent(CameraComponent).?;
        if (camera_component.mIsFixedAspectRatio == false) {
            camera_component.SetViewportSize(viewport_width, viewport_height);
        }
    }
}

pub fn NewScene(self: *SceneManager, engine_context: *EngineContext, layer_type: LayerType) !SceneLayer {
    const new_scene_id = try self.mECSManagerSC.CreateEntity();
    const scene_layer = SceneLayer{ .mSceneID = new_scene_id, .mECSManagerGORef = &self.mECSManagerGO, .mECSManagerSCRef = &self.mECSManagerSC };

    const new_scene_component = SceneComponent{
        .mLayerType = layer_type,
    };
    _ = try scene_layer.AddComponent(SceneComponent, new_scene_component);

    _ = try scene_layer.AddComponent(SceneIDComponent, .{ .ID = try GenUUID() });

    const scene_name_component = try scene_layer.AddComponent(SceneNameComponent, .{ .mAllocator = engine_context.EngineAllocator() });
    _ = try scene_name_component.mName.writer(scene_name_component.mAllocator).write("Unsaved Scene");

    _ = try scene_layer.AddComponent(SceneTransformComponent, null);

    try self.InsertScene(engine_context.FrameAllocator(), scene_layer);

    return scene_layer;
}

pub fn RemoveScene(self: *SceneManager, engine_context: *EngineContext, destroy_scene: SceneLayer) !void {
    try self.SaveScene(engine_context, destroy_scene);

    const frame_allocator = engine_context.FrameAllocator();

    //remove all the entities from the scene
    var entity_scene_entities = try self.mECSManagerGO.GetGroup(frame_allocator, .{ .Component = EntitySceneComponent });
    defer entity_scene_entities.deinit(frame_allocator);

    self.FilterEntityByScene(frame_allocator, &entity_scene_entities, destroy_scene.mSceneID);

    for (entity_scene_entities.items) |entity_id| {
        const entity = self.GetEntity(entity_id);
        try self.DestroyEntity(engine_context.EngineAllocator(), entity);
    }

    //next realign the scene stack so that everything is in the right position after this one is destroyed
    const destroy_stack_pos = destroy_scene.GetComponent(SceneStackPos).?;

    var stack_pos_group = try self.mECSManagerSC.GetGroup(frame_allocator, .{ .Component = SceneStackPos });
    defer stack_pos_group.deinit(frame_allocator);

    for (stack_pos_group.items) |pos_scene_id| {
        const stack_pos = self.mECSManagerSC.GetComponent(SceneStackPos, pos_scene_id).?;
        if (stack_pos.mPosition > destroy_stack_pos.mPosition) {
            stack_pos.mPosition -= 1;
        }
    }

    //finally destroy the scene
    try self.mECSManagerSC.DestroyEntity(engine_context.EngineAllocator(), destroy_scene.mSceneID);
}

pub fn LoadScene(self: *SceneManager, engine_context: *EngineContext, path: []const u8) !SceneLayer.Type {
    const new_scene_id = try self.mECSManagerSC.CreateEntity();
    const scene_layer = SceneLayer{ .mSceneID = new_scene_id, .mECSManagerGORef = &self.mECSManagerGO, .mECSManagerSCRef = &self.mECSManagerSC };
    const scene_asset_handle = try engine_context.mAssetManager.GetAssetHandleRef(engine_context.EngineAllocator(), path, .Prj);

    const scene_basename = std.fs.path.basename(path);
    const dot_location = std.mem.indexOf(u8, scene_basename, ".") orelse 0;
    const scene_name = scene_basename[0..dot_location];

    const new_scene_name_component = try scene_layer.AddComponent(SceneNameComponent, .{ .mAllocator = engine_context.EngineAllocator() });
    _ = try new_scene_name_component.mName.writer(new_scene_name_component.mAllocator).write(scene_name);

    try SceneSerializer.DeSerializeSceneText(engine_context, scene_layer, scene_asset_handle);

    try self.InsertScene(engine_context.FrameAllocator(), scene_layer);

    return new_scene_id;
}

pub fn SaveAllScenes(self: *SceneManager, engine_context: *EngineContext) !void {
    const frame_allocator = engine_context.FrameAllocator();
    const all_scenes = try self.mECSManagerSC.GetGroup(
        frame_allocator,
        GroupQuery{ .Component = SceneStackPos },
    );

    for (all_scenes.items) |scene_id| {
        const scene = self.GetSceneLayer(scene_id);

        try self.SaveScene(engine_context, scene);
    }
}

pub fn ReloadAllScenes(self: *SceneManager, engine_context: *EngineContext) !void {
    self.mECSManagerGO.clearAndFree(engine_context);

    const all_scenes = try self.mECSManagerSC.GetGroup(engine_context.FrameAllocator(), GroupQuery{ .Component = SceneStackPos });

    for (all_scenes.items) |scene_id| {
        const scene = self.GetSceneLayer(scene_id);
        const scene_component = scene.GetComponent(SceneComponent).?;

        try SceneSerializer.SceneReloadText(engine_context, scene, scene_component.mSceneAssetHandle);
    }
}
pub fn SaveScene(self: *SceneManager, engine_context: *EngineContext, scene_layer: SceneLayer) !void {
    const frame_allocator = engine_context.FrameAllocator();
    const scene_component = scene_layer.GetComponent(SceneComponent).?;
    if (scene_component.mSceneAssetHandle.mID != AssetHandle.NullHandle) {
        const file_data = try scene_component.mSceneAssetHandle.GetAsset(engine_context, FileMetaData);
        const abs_path = try engine_context.mAssetManager.GetAbsPath(file_data.mRelPath.items, .Prj, frame_allocator);
        try SceneSerializer.SerializeSceneText(scene_layer, abs_path, frame_allocator);
    } else {
        var buffer: [260]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);
        const abs_path = try PlatformUtils.SaveFile(fba.allocator(), ".imsc");
        if (abs_path.len > 0) {
            try self.SaveSceneAs(scene_layer, abs_path, frame_allocator);
        }
    }
}
pub fn SaveSceneAs(_: *SceneManager, scene_layer: SceneLayer, abs_path: []const u8, frame_allocator: std.mem.Allocator) !void {
    const scene_basename = std.fs.path.basename(abs_path);
    const dot_location = std.mem.indexOf(u8, scene_basename, ".") orelse 0;
    const scene_name = scene_basename[0..dot_location];

    const scene_name_component = scene_layer.GetComponent(SceneNameComponent).?;
    scene_name_component.mName.clearAndFree(scene_name_component.mAllocator);
    _ = try scene_name_component.mName.writer(scene_name_component.mAllocator).write(scene_name);

    try SceneSerializer.SerializeSceneText(scene_layer, abs_path, frame_allocator);
}

pub fn MoveScene(self: *SceneManager, frame_allocator: std.mem.Allocator, scene_id: SceneLayer.Type, move_to_pos: usize) !void {
    const scene_component = self.mECSManagerSC.GetComponent(SceneComponent, scene_id).?;
    const stack_pos_component = self.mECSManagerSC.GetComponent(SceneStackPos, scene_id).?;
    const current_pos = stack_pos_component.mPosition;

    var new_pos: usize = 0;
    if (scene_component.mLayerType == .OverlayLayer and move_to_pos < self.mGameLayerInsertIndex) {
        new_pos = self.mGameLayerInsertIndex;
    } else if (scene_component.mLayerType == .GameLayer and move_to_pos >= self.mGameLayerInsertIndex) {
        new_pos = self.mGameLayerInsertIndex - 1;
    } else {
        new_pos = move_to_pos;
    }

    if (new_pos == current_pos) {
        return;
    } else if (new_pos < current_pos) {
        //we are moving the scene down in position so we need to move everything between new_pos and current_pos up 1 position
        const scene_stack_pos_list = try self.mECSManagerSC.GetGroup(frame_allocator, .{ .Component = SceneStackPos });

        for (scene_stack_pos_list.items) |list_scene_id| {
            const scene_stack_pos_component = self.mECSManagerSC.GetComponent(SceneStackPos, list_scene_id).?;
            if (scene_stack_pos_component.mPosition >= new_pos and scene_stack_pos_component.mPosition < current_pos) {
                scene_stack_pos_component.mPosition += 1;
            }
        }
    } else {
        //we are moving the scene up in position so we need to move everything between current_pos and new_pos down 1 position
        const scene_stack_pos_list = try self.mECSManagerSC.GetGroup(frame_allocator, .{ .Component = SceneStackPos });

        for (scene_stack_pos_list.items) |list_scene_id| {
            const scene_stack_pos_component = self.mECSManagerSC.GetComponent(SceneStackPos, list_scene_id).?;
            if (scene_stack_pos_component.mPosition > current_pos and scene_stack_pos_component.mPosition <= new_pos) {
                scene_stack_pos_component.mPosition -= 1;
            }
        }
    }

    stack_pos_component.mPosition = new_pos;
}

pub fn SaveEntity(self: *SceneManager, frame_allocator: std.mem.Allocator, entity: Entity) !void {
    var buffer: [260]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const abs_path = try PlatformUtils.SaveFile(fba.allocator(), ".imsc");
    try self.SaveEntityAs(frame_allocator, entity, abs_path);
}

pub fn SaveEntityAs(_: *SceneManager, frame_allocator: std.mem.Allocator, entity: Entity, abs_path: []const u8) !void {
    try SceneSerializer.SerializeEntityText(frame_allocator, entity, abs_path);
}

pub fn FilterEntityByScene(self: *SceneManager, list_allocator: std.mem.Allocator, entity_result_list: *std.ArrayList(Entity.Type), scene_id: SceneLayer.Type) void {
    const zone = Tracy.ZoneInit("SceneManager::FilterEntityByScene", @src());
    defer zone.Deinit();
    const scene_layer = SceneLayer{ .mSceneID = scene_id, .mECSManagerGORef = &self.mECSManagerGO, .mECSManagerSCRef = &self.mECSManagerSC };
    scene_layer.FilterEntityByScene(list_allocator, entity_result_list);
}

pub fn FilterEntityScriptsByScene(self: *SceneManager, list_allocator: std.mem.Allocator, scripts_result_list: *std.ArrayList(Entity.Type), scene_id: SceneLayer.Type) void {
    const zone = Tracy.ZoneInit("SceneManager::FilterEntityScriptsByScene", @src());
    defer zone.Deinit();
    const scene_layer = SceneLayer{ .mSceneID = scene_id, .mECSManagerGORef = &self.mECSManagerGO, .mECSManagerSCRef = &self.mECSManagerSC };
    scene_layer.FilterEntityScriptsByScene(list_allocator, scripts_result_list);
}

pub fn FilterSceneScriptsByScene(self: *SceneManager, list_allocator: std.mem.Allocator, scripts_result_list: *std.ArrayList(Entity.Type), scene_id: SceneLayer.Type) void {
    const zone = Tracy.ZoneInit("SceneManager::FilterSceneScriptsByScene", @src());
    defer zone.Deinit();
    const scene_layer = SceneLayer{ .mSceneID = scene_id, .mECSManagerGORef = &self.mECSManagerGO, .mECSManagerSCRef = &self.mECSManagerSC };
    scene_layer.FilterSceneScriptsByScene(list_allocator, scripts_result_list);
}

pub fn GetEntityGroup(self: *SceneManager, frame_allocator: std.mem.Allocator, query: GroupQuery) !std.ArrayList(Entity.Type) {
    const zone = Tracy.ZoneInit("SceneManager GetEntityGroup", @src());
    defer zone.Deinit();
    return try self.mECSManagerGO.GetGroup(frame_allocator, query);
}

pub fn SortScenesFunc(ecs_manager_sc: ECSManagerScenes, a: SceneLayer.Type, b: SceneLayer.Type) bool {
    const a_stack_pos_comp = ecs_manager_sc.GetComponent(SceneStackPos, a).?;
    const b_stack_pos_comp = ecs_manager_sc.GetComponent(SceneStackPos, b).?;

    return (b_stack_pos_comp.mPosition < a_stack_pos_comp.mPosition);
}

pub fn GetEntity(self: *SceneManager, entity_id: Entity.Type) Entity {
    return Entity{ .mEntityID = entity_id, .mECSManagerRef = &self.mECSManagerGO };
}

pub fn GetSceneLayer(self: *SceneManager, scene_id: SceneLayer.Type) SceneLayer {
    return SceneLayer{ .mSceneID = scene_id, .mECSManagerGORef = &self.mECSManagerGO, .mECSManagerSCRef = &self.mECSManagerSC };
}

pub fn RmEntityComp(self: *SceneManager, engine_allocator: std.mem.Allocator, entity_id: Entity.Type, component_ind: EEntityComponents) !void {
    try self.mECSManagerGO.RemoveComponentInd(engine_allocator, entity_id, @intFromEnum(component_ind));
}

pub fn RmSceneComp(self: *SceneManager, engine_allocator: std.mem.Allocator, scene_id: SceneLayer.Type, component_ind: ESceneComponents) !void {
    try self.mECSManagerSC.RemoveComponentInd(engine_allocator, scene_id, @intFromEnum(component_ind));
}

pub fn ProcessRemovedObj(self: *SceneManager, engine_context: *EngineContext) !void {
    try self.mECSManagerGO.ProcessEvents(engine_context, .EC_RemoveObj);
    try self.mECSManagerSC.ProcessEvents(engine_context, .EC_RemoveObj);
}

fn InsertScene(self: *SceneManager, frame_allocator: std.mem.Allocator, scene_layer: SceneLayer) !void {
    const scene_component = scene_layer.GetComponent(SceneComponent).?;
    if (scene_component.mLayerType == .GameLayer) {
        _ = try scene_layer.AddComponent(SceneStackPos, .{ .mPosition = self.mGameLayerInsertIndex });
        const stack_pos_group = try self.mECSManagerSC.GetGroup(frame_allocator, .{ .Component = SceneStackPos });
        for (stack_pos_group.items) |scene_id| {
            const stack_pos = self.mECSManagerSC.GetComponent(SceneStackPos, scene_id).?;
            if (stack_pos.mPosition >= self.mGameLayerInsertIndex) {
                stack_pos.mPosition += 1;
            }
        }
        self.mGameLayerInsertIndex += 1;
    } else {
        _ = try scene_layer.AddComponent(SceneStackPos, .{ .mPosition = self.mNumofLayers });
    }
    self.mNumofLayers += 1;
}

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
const TransformComponent = EntityComponents.TransformComponent;
const CameraComponent = EntityComponents.CameraComponent;
const OnInputPressedScript = EntityComponents.OnInputPressedScript;
const EntityScriptComponent = EntityComponents.ScriptComponent;
const EntitySceneComponent = EntityComponents.SceneIDComponent;
const EntityParentComponent = EntityComponents.ParentComponent;
const EntityChildComponent = EntityComponents.ChildComponent;

const SceneComponents = @import("SceneComponents.zig");
const SceneComponentsList = SceneComponents.ComponentsList;
const SceneComponent = SceneComponents.SceneComponent;
const SceneIDComponent = SceneComponents.IDComponent;
const SceneNameComponent = SceneComponents.NameComponent;
const SceneStackPos = SceneComponents.StackPosComponent;
const SceneScriptComponent = SceneComponents.ScriptComponent;

const AssetManager = @import("../Assets/AssetManager.zig");
const Assets = @import("../Assets/Assets.zig");
const AssetHandle = @import("../Assets/AssetHandle.zig");
const ScriptAsset = Assets.ScriptAsset;
const SceneAsset = Assets.SceneAsset;
const ShaderAsset = Assets.ShaderAsset;

const RenderManager = @import("../Renderer/Renderer.zig");

const InputPressedEvent = @import("../Events/SystemEvent.zig").InputPressedEvent;

const Tracy = @import("../Core/Tracy.zig");

const SceneManager = @This();

pub const ECSManagerGameObj = ECSManager(Entity.Type, EntityComponentsArray.len);

pub const SceneType = u32;
pub const ECSManagerScenes = ECSManager(SceneType, EntityComponentsArray.len);

//scene stuff
mECSManagerGO: ECSManagerGameObj,
mECSManagerSC: ECSManagerScenes,
mGameLayerInsertIndex: usize,
mNumofLayers: usize,

//viewport stuff
mViewportWidth: usize,
mViewportHeight: usize,

mEngineAllocator: std.mem.Allocator,

pub fn Init(width: usize, height: usize, engine_allocator: std.mem.Allocator) !SceneManager {
    return SceneManager{
        .mECSManagerGO = try ECSManagerGameObj.Init(engine_allocator, &EntityComponentsArray),
        .mECSManagerSC = try ECSManagerScenes.Init(engine_allocator, &SceneComponentsList),
        .mGameLayerInsertIndex = 0,
        .mNumofLayers = 0,
        .mViewportWidth = width,
        .mViewportHeight = height,
        .mEngineAllocator = engine_allocator,
    };
}

pub fn Deinit(self: *SceneManager) !void {
    self.mECSManagerGO.Deinit();
    self.mECSManagerSC.Deinit();
}

pub fn CreateEntity(self: *SceneManager, scene_id: SceneType) !Entity {
    const scene_layer = SceneLayer{ .mSceneID = scene_id, .mECSManagerGORef = &self.mECSManagerGO, .mECSManagerSCRef = &self.mECSManagerSC };
    return scene_layer.CreateEntity();
}
pub fn CreateEntityWithUUID(self: *SceneManager, uuid: u128, scene_id: SceneType) !Entity {
    const scene_layer = SceneLayer{ .mSceneID = scene_id, .mECSManagerGORef = &self.mECSManagerGO, .mECSManagerSCRef = &self.mECSManagerSC };
    return scene_layer.CreateEntityWithUUID(uuid);
}

pub fn DestroyEntity(self: *SceneManager, e: Entity, scene_id: SceneType) !void {
    const scene_layer = SceneLayer{ .mSceneID = scene_id, .mECSManagerGORef = &self.mECSManagerGO, .mECSManagerSCRef = &self.mECSManagerSC };
    scene_layer.DestroyEntity(e);
}
pub fn DuplicateEntity(self: *SceneManager, original_entity: Entity, scene_id: SceneType) !Entity {
    const scene_layer = SceneLayer{ .mSceneID = scene_id, .mECSManagerGORef = &self.mECSManagerGO, .mECSManagerSCRef = &self.mECSManagerSC };
    scene_layer.DuplicateEntity(original_entity);
}

pub fn OnViewportResize(self: *SceneManager, viewport_width: usize, viewport_height: usize, frame_allocator: std.mem.Allocator) !void {
    self.mViewportWidth = viewport_width;
    self.mViewportHeight = viewport_height;

    const camera_group = try self.mECSManagerGO.GetGroup(.{ .Component = CameraComponent }, frame_allocator);
    for (camera_group.items) |entity_id| {
        const entity = Entity{ .mEntityID = entity_id, .mECSManagerRef = &self.mECSManagerGO };
        const camera_component = entity.GetComponent(CameraComponent);
        if (camera_component.mIsFixedAspectRatio == false) {
            camera_component.SetViewportSize(viewport_width, viewport_height);
        }
    }
}

pub fn NewScene(self: *SceneManager, layer_type: LayerType) !SceneLayer {
    const new_scene_id = try self.mECSManagerSC.CreateEntity();
    const scene_layer = SceneLayer{ .mSceneID = new_scene_id, .mECSManagerGORef = &self.mECSManagerGO, .mECSManagerSCRef = &self.mECSManagerSC };

    const new_scene_component = SceneComponent{
        .mLayerType = layer_type,
    };
    _ = try scene_layer.AddComponent(SceneComponent, new_scene_component);

    _ = try scene_layer.AddComponent(SceneIDComponent, .{ .ID = try GenUUID() });

    const scene_name_component = try scene_layer.AddComponent(SceneNameComponent, .{ .Name = std.ArrayList(u8).init(self.mEngineAllocator) });
    scene_name_component.Name.clearAndFree();
    _ = try scene_name_component.Name.writer().write("Unsaved Scene");

    try self.InsertScene(scene_layer);

    return scene_layer;
}

pub fn RemoveScene(self: *SceneManager, scene_id: usize) !void {
    self.SaveScene(scene_id);

    const entity_scene_entities = try self.mECSManagerGO.GetGroup(.{ .Component = EntitySceneComponent }, self.mEngineAllocator);
    defer entity_scene_entities.deinit();

    self.FilterEntityByScene(entity_scene_entities, scene_id);

    for (entity_scene_entities.mEntityList.items) |entity_id| {
        self.mECSManagerGO.DestroyEntity(entity_id);
    }

    self.mECSManagerSC.DestroyEntity(scene_id);
}

pub fn LoadScene(self: *SceneManager, path: []const u8, engine_allocator: std.mem.Allocator, frame_allocator: std.mem.Allocator) !SceneType {
    const new_scene_id = try self.mECSManagerSC.CreateEntity();
    const scene_layer = SceneLayer{ .mSceneID = new_scene_id, .mECSManagerGORef = &self.mECSManagerGO, .mECSManagerSCRef = &self.mECSManagerSC };
    const scene_asset_handle = try AssetManager.GetAssetHandleRef(path, .Prj);
    const scene_asset = try scene_asset_handle.GetAsset(SceneAsset);

    const new_scene_component = SceneComponent{
        .mSceneAssetHandle = scene_asset_handle,
        .mLayerType = undefined,
    };

    _ = try scene_layer.AddComponent(SceneComponent, new_scene_component);

    _ = try scene_layer.AddComponent(SceneIDComponent, .{ .ID = undefined });

    const scene_basename = std.fs.path.basename(path);
    const dot_location = std.mem.indexOf(u8, scene_basename, ".") orelse 0;
    const scene_name = scene_basename[0..dot_location];
    var new_scene_name_component = SceneNameComponent{ .Name = std.ArrayList(u8).init(self.mEngineAllocator) };
    _ = try new_scene_name_component.Name.writer().write(scene_name);

    _ = try scene_layer.AddComponent(SceneNameComponent, new_scene_name_component);

    try SceneSerializer.DeSerializeSceneText(scene_layer, scene_asset, frame_allocator, engine_allocator);

    try self.InsertScene(scene_layer);

    return new_scene_id;
}

pub fn SaveAllScenes(self: *SceneManager, frame_allocator: std.mem.Allocator) !void {
    const all_scenes = try self.mECSManagerSC.GetGroup(GroupQuery{ .Component = SceneStackPos }, frame_allocator);

    for (all_scenes.items) |scene_id| {
        const scene = self.GetSceneLayer(scene_id);

        try self.SaveScene(scene, frame_allocator);
    }
}

pub fn ReloadAllScenes(self: *SceneManager, frame_allocator: std.mem.Allocator) !void {
    self.mECSManagerGO.clearAndFree();

    const all_scenes = try self.mECSManagerSC.GetGroup(GroupQuery{ .Component = SceneStackPos }, frame_allocator);

    for (all_scenes.items) |scene_id| {
        const scene = self.GetSceneLayer(scene_id);
        const scene_component = scene.GetComponent(SceneComponent);
        if (scene_component.mSceneAssetHandle.mID != AssetHandle.NullHandle) {
            const scene_asset = try scene_component.mSceneAssetHandle.GetAsset(SceneAsset);

            try SceneSerializer.DeSerializeSceneText(scene, scene_asset, frame_allocator, self.mEngineAllocator);
        }
    }
}
pub fn SaveScene(self: *SceneManager, scene_layer: SceneLayer, frame_allocator: std.mem.Allocator) !void {
    const scene_component = scene_layer.GetComponent(SceneComponent);
    if (scene_component.mSceneAssetHandle.mID != AssetHandle.NullHandle) {
        try SceneSerializer.SerializeSceneText(scene_layer, scene_component.mSceneAssetHandle, frame_allocator);
    } else {
        var buffer: [260]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);
        const abs_path = try PlatformUtils.SaveFile(fba.allocator(), ".imsc");
        const rel_path = AssetManager.GetRelPath(abs_path);
        _ = try std.fs.createFileAbsolute(abs_path, .{});
        scene_component.mSceneAssetHandle = try AssetManager.GetAssetHandleRef(rel_path, .Prj);
        try self.SaveSceneAs(scene_layer, abs_path, frame_allocator);
    }
}
pub fn SaveSceneAs(_: *SceneManager, scene_layer: SceneLayer, abs_path: []const u8, frame_allocator: std.mem.Allocator) !void {
    const scene_component = scene_layer.GetComponent(SceneComponent);
    const scene_basename = std.fs.path.basename(abs_path);
    const dot_location = std.mem.indexOf(u8, scene_basename, ".") orelse 0;
    const scene_name = scene_basename[0..dot_location];

    const scene_name_component = scene_layer.GetComponent(SceneNameComponent);
    scene_name_component.Name.clearAndFree();
    _ = try scene_name_component.Name.writer().write(scene_name);

    try SceneSerializer.SerializeSceneText(scene_layer, scene_component.mSceneAssetHandle, frame_allocator);
}

pub fn MoveScene(self: *SceneManager, scene_id: SceneType, move_to_pos: usize) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const scene_component = self.mECSManagerSC.GetComponent(SceneComponent, scene_id);
    const stack_pos_component = self.mECSManagerSC.GetComponent(SceneStackPos, scene_id);
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
        const scene_stack_pos_list = try self.mECSManagerSC.GetGroup(.{ .Component = SceneStackPos }, allocator);

        for (scene_stack_pos_list.items) |list_scene_id| {
            const scene_stack_pos_component = self.mECSManagerSC.GetComponent(SceneStackPos, list_scene_id);
            if (scene_stack_pos_component.mPosition >= new_pos and scene_stack_pos_component.mPosition < current_pos) {
                scene_stack_pos_component.mPosition += 1;
            }
        }
    } else {
        //we are moving the scene up in position so we need to move everything between current_pos and new_pos down 1 position
        const scene_stack_pos_list = try self.mECSManagerSC.GetGroup(.{ .Component = SceneStackPos }, allocator);

        for (scene_stack_pos_list.items) |list_scene_id| {
            const scene_stack_pos_component = self.mECSManagerSC.GetComponent(SceneStackPos, list_scene_id);
            if (scene_stack_pos_component.mPosition > current_pos and scene_stack_pos_component.mPosition <= new_pos) {
                scene_stack_pos_component.mPosition -= 1;
            }
        }
    }

    stack_pos_component.mPosition = new_pos;
}

pub fn SaveEntity(self: *SceneManager, entity: Entity, frame_allocator: std.mem.Allocator) !void {
    var buffer: [260]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const abs_path = try PlatformUtils.SaveFile(fba.allocator(), ".imsc");
    try self.SaveEntityAs(entity, abs_path, frame_allocator);
}

pub fn SaveEntityAs(_: *SceneManager, entity: Entity, abs_path: []const u8, frame_allocator: std.mem.Allocator) !void {
    try SceneSerializer.SerializeEntityText(entity, abs_path, frame_allocator);
}

pub fn FilterEntityByScene(self: *SceneManager, entity_result_list: *std.ArrayList(Entity.Type), scene_id: SceneType) void {
    const scene_layer = SceneLayer{ .mSceneID = scene_id, .mECSManagerGORef = &self.mECSManagerGO, .mECSManagerSCRef = &self.mECSManagerSC };
    scene_layer.FilterEntityByScene(entity_result_list);
}

pub fn FilterEntityScriptsByScene(self: *SceneManager, scripts_result_list: *std.ArrayList(Entity.Type), scene_id: SceneType) void {
    const scene_layer = SceneLayer{ .mSceneID = scene_id, .mECSManagerGORef = &self.mECSManagerGO, .mECSManagerSCRef = &self.mECSManagerSC };
    scene_layer.FilterEntityScriptsByScene(scripts_result_list);
}

pub fn FilterSceneScriptsByScene(self: *SceneManager, scripts_result_list: *std.ArrayList(Entity.Type), scene_id: SceneType) void {
    const scene_layer = SceneLayer{ .mSceneID = scene_id, .mECSManagerGORef = &self.mECSManagerGO, .mECSManagerSCRef = &self.mECSManagerSC };
    scene_layer.FilterSceneScriptsByScene(scripts_result_list);
}

pub fn GetEntityGroup(self: *SceneManager, query: GroupQuery, frame_allocator: std.mem.Allocator) !std.ArrayList(Entity.Type) {
    const zone = Tracy.ZoneInit("SceneManager GetEntityGroup", @src());
    defer zone.Deinit();
    return try self.mECSManagerGO.GetGroup(query, frame_allocator);
}

pub fn SortScenesFunc(ecs_manager_sc: ECSManagerScenes, a: SceneType, b: SceneType) bool {
    const a_stack_pos_comp = ecs_manager_sc.GetComponent(SceneStackPos, a);
    const b_stack_pos_comp = ecs_manager_sc.GetComponent(SceneStackPos, b);

    return (b_stack_pos_comp.mPosition < a_stack_pos_comp.mPosition);
}

pub fn GetEntity(self: *SceneManager, entity_id: Entity.Type) Entity {
    return Entity{ .mEntityID = entity_id, .mECSManagerRef = &self.mECSManagerGO };
}

pub fn GetSceneLayer(self: *SceneManager, scene_id: SceneType) SceneLayer {
    return SceneLayer{ .mSceneID = scene_id, .mECSManagerGORef = &self.mECSManagerGO, .mECSManagerSCRef = &self.mECSManagerSC };
}

fn InsertScene(self: *SceneManager, scene_layer: SceneLayer) !void {
    const scene_component = scene_layer.GetComponent(SceneComponent);
    if (scene_component.mLayerType == .GameLayer) {
        _ = try scene_layer.AddComponent(SceneStackPos, .{ .mPosition = self.mGameLayerInsertIndex });
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();
        const stack_pos_group = try self.mECSManagerSC.GetGroup(.{ .Component = SceneStackPos }, allocator);
        for (stack_pos_group.items) |scene_id| {
            const stack_pos = self.mECSManagerSC.GetComponent(SceneStackPos, scene_id);
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

fn CalculateEntityTransform(entity: Entity, parent_transform: Mat4f32, parent_dirty: bool) void {
    const transform_component = entity.GetComponent(TransformComponent);
    defer transform_component.Dirty = false;
    if (transform_component.Dirty or parent_dirty) {
        transform_component.WorldTransform = LinAlg.Mat4MulMat4(parent_transform, transform_component.GetLocalTransform());
    }
    if (entity.HasComponent(EntityParentComponent)) {
        const parent_component = entity.GetComponent(EntityParentComponent);

        var curr_id = parent_component.mFirstChild;
        while (curr_id != Entity.NullEntity) {
            const child_entity = Entity{ .mEntityID = curr_id, .mECSManagerRef = entity.mECSManagerRef };
            CalculateEntityTransform(child_entity, transform_component.WorldTransform, transform_component.Dirty);

            const child_component = child_entity.GetComponent(EntityChildComponent);
            curr_id = child_component.mNext;
        }
    }
}

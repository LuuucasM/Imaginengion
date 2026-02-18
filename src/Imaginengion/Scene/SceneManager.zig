const std = @import("std");
const LinAlg = @import("../Math/LinAlg.zig");
const Vec2f32 = LinAlg.Vec2f32;
const Vec3f32 = LinAlg.Vec3f32;
const Mat4f32 = LinAlg.Mat4f32;

const SceneLayer = @import("SceneLayer.zig");
const LayerType = @import("Components/SceneComponent.zig").LayerType;
const PlatformUtils = @import("../PlatformUtils/PlatformUtils.zig");
const GenUUID = @import("../Core/UUID.zig").GenUUID;

const ECSManager = @import("../ECS/ECSManager.zig").ECSManager;
const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;
const Entity = @import("../GameObjects/Entity.zig");
const ChildType = @import("../ECS/ECSManager.zig").ChildType;

const EntityComponents = @import("../GameObjects/Components.zig");
const EntityComponentsArray = EntityComponents.ComponentsList;
const EEntityComponents = EntityComponents.EComponents;
const EntityTransformComponent = EntityComponents.TransformComponent;
const EntityScriptComponent = EntityComponents.ScriptComponent;
const EntitySceneComponent = EntityComponents.EntitySceneComponent;
const EntityParentComponent = @import("../ECS/Components.zig").ParentComponent(Entity.Type);
const EntityChildComponent = @import("../ECS/Components.zig").ChildComponent(Entity.Type);
const EntityAISlotComponent = EntityComponents.AISlotComponent;
const EntityNameComponent = EntityComponents.NameComponent;
const EntityPlayerSlotComponent = EntityComponents.PlayerSlotComponent;
const EntityQuadComponent = EntityComponents.QuadComponent;
const EntityUUIDComponent = EntityComponents.UUIDComponent;

const SceneComponents = @import("SceneComponents.zig");
const SceneComponentsList = SceneComponents.ComponentsList;
const ESceneComponents = SceneComponents.EComponents;
const SceneComponent = SceneComponents.SceneComponent;
const SceneUUIDComponent = SceneComponents.UUIDComponent;
const SceneNameComponent = SceneComponents.NameComponent;
const SceneStackPos = SceneComponents.StackPosComponent;
//const SceneTransformComponent = SceneComponents.TransformComponent;
const SceneScriptComponent = SceneComponents.ScriptComponent;

const Assets = @import("../Assets/Assets.zig");
const AssetHandle = @import("../Assets/AssetHandle.zig");
const ScriptAsset = Assets.ScriptAsset;
const SceneAsset = Assets.SceneAsset;
const FileMetaData = Assets.FileMetaData;
const EngineContext = @import("../Core/EngineContext.zig");

const Player = @import("../Players/Player.zig");
const PlayerComponents = @import("../Players/Components.zig").ComponentsList;
const PlayerLens = PlayerComponents.LensComponent;
const PossessComponent = PlayerComponents.PossessComponent;
const PlayerMic = PlayerComponents.MicComponent;
const PlayerUtils = @import("../Players/PlayerUtils.zig");

const InputPressedEvent = @import("../Events/SystemEvent.zig").InputPressedEvent;

const Tracy = @import("../Core/Tracy.zig");

const NewSceneConfig = SceneLayer.NewSceneConfig;

const SceneManager = @This();

pub const ECSManagerGameObj = ECSManager(Entity.Type, &EntityComponentsArray);
pub const ECSManagerScenes = ECSManager(SceneLayer.Type, &SceneComponentsList);
pub const ECSManagerPlayer = ECSManager(Player.Type, &PlayerComponents.ComponentsList);

//scene stuff
mECSManagerGO: ECSManagerGameObj = .{},
mECSManagerSC: ECSManagerScenes = .{},
mECSManagerPL: ECSManagerPlayer = .{},
mSceneUUIDToWorldID: std.AutoHashMapUnmanaged(u64, SceneLayer.Type) = .{},
mEntityUUIDToWorldID: std.AutoHashMapUnmanaged(u64, Entity.Type) = .{},

mGameLayerInsertIndex: usize = 0,
mNumofLayers: usize = 0,

//viewport stuff
mViewportWidth: usize = 0,
mViewportHeight: usize = 0,

pub fn Init(self: *SceneManager, width: usize, height: usize, engine_allocator: std.mem.Allocator) !void {
    try self.mECSManagerGO.Init(engine_allocator);
    try self.mECSManagerSC.Init(engine_allocator);
    try self.mECSManagerPL.Init(engine_allocator);
    self.mViewportWidth = width;
    self.mViewportHeight = height;
}

pub fn Deinit(self: *SceneManager, engine_context: *EngineContext) !void {
    try self.mECSManagerGO.Deinit(engine_context);
    try self.mECSManagerSC.Deinit(engine_context);
    try self.mECSManagerPL.Deinit(engine_context);

    self.mSceneUUIDToWorldID.deinit(engine_context.EngineAllocator());
    self.mEntityUUIDToWorldID.deinit(engine_context.EngineAllocator());
}

//===============================ECS MANAGER SC==============================================
pub fn NewScene(self: *SceneManager, engine_context: *EngineContext, _: LayerType, new_scene_config: NewSceneConfig) !SceneLayer {
    const scene_layer = SceneLayer{ .mSceneID = try self.mECSManagerSC.CreateEntity(), .mECSManagerGORef = &self.mECSManagerGO, .mECSManagerSCRef = &self.mECSManagerSC };
    _ = try scene_layer.AddComponent(SceneComponent{});

    self.CreateSceneConfig(engine_context.EngineAllocator(), scene_layer, new_scene_config);

    try self.InsertScene(engine_context.FrameAllocator(), scene_layer);

    return scene_layer;
}

pub fn DestroyScene(self: *SceneManager, engine_context: *EngineContext, destroy_scene: SceneLayer) !void {
    try self.SaveScene(engine_context, destroy_scene);

    const frame_allocator = engine_context.FrameAllocator();

    //remove all the UUIDs in the UUID map
    const uuid_entities = try destroy_scene.GetEntityGroup(frame_allocator, EntityUUIDComponent);
    for (uuid_entities.items) |entity_id| {
        const entity = Entity{ .mEntityID = entity_id, .mECSManagerRef = destroy_scene.mECSManagerGORef };
        const uuid_component = entity.GetComponent(EntityUUIDComponent).?;
        _ = self.mEntityUUIDToWorldID.remove(uuid_component.ID);
    }

    const scene_uuid = destroy_scene.GetComponent(SceneUUIDComponent).?;
    _ = self.mSceneUUIDToWorldID.remove(scene_uuid.ID);

    //remove all the entities from the scene
    const entity_scene_entities = try destroy_scene.GetEntityGroup(frame_allocator, EntitySceneComponent);

    for (entity_scene_entities.items) |entity_id| {
        const entity = self.GetEntity(entity_id);
        try self.DestroyEntity(engine_context.EngineAllocator(), entity);
    }

    try self.RemoveScene(engine_context.FrameAllocator(), destroy_scene);

    //finally destroy the scene
    try self.mECSManagerSC.DestroyEntity(engine_context.EngineAllocator(), destroy_scene.mSceneID);
}

pub fn LoadScene(self: *SceneManager, engine_context: *EngineContext, abs_path: []const u8) !SceneLayer {
    const scene_layer = try self.NewBlankScene(engine_context, .GameLayer);

    try engine_context.mSceneSerializer.DeSerializeSceneText(engine_context, scene_layer, abs_path);

    const scene_uuid_comp = scene_layer.GetComponent(SceneUUIDComponent).?;
    self.mSceneUUIDToWorldID.put(engine_context.EngineAllocator(), scene_uuid_comp.ID, scene_layer.mSceneID);

    const entity_uuids = try scene_layer.GetEntityGroup(engine_context.FrameAllocator(), .{ .Component = EntityUUIDComponent });
    for (entity_uuids) |entity_id| {
        const entity = self.GetEntity(entity_id);
        const entity_uuid = entity.GetComponent(EntityUUIDComponent).?;
        self.mEntityUUIDToWorldID.put(engine_context.EngineAllocator(), entity_uuid.ID, entity.mEntityID);
    }

    try self.InsertScene(engine_context.FrameAllocator(), scene_layer);

    return scene_layer;
}

pub fn Serialize(self: *SceneManager, engine_context: *EngineContext) !void {
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

pub fn SaveScene(self: *SceneManager, engine_context: *EngineContext, scene_layer: SceneLayer) !void {
    const frame_allocator = engine_context.FrameAllocator();
    const scene_component = scene_layer.GetComponent(SceneComponent).?;

    if (scene_component.mScenePath.items.len != 0) {
        const abs_path = try engine_context.mAssetManager.GetAbsPath(frame_allocator, scene_component.mScenePath.items, .Prj);
        try engine_context.mSceneSerializer.SerializeSceneText(frame_allocator, scene_layer, abs_path);
    } else {
        try self.SaveSceneAs(engine_context, scene_layer);
    }
}

pub fn SaveSceneAs(_: *SceneManager, engine_context: *EngineContext, scene_layer: SceneLayer) !void {
    const abs_path = try PlatformUtils.SaveFile(engine_context.FrameAllocator(), ".imsc");
    if (abs_path.len > 0) {
        try engine_context.mSceneSerializer.SerializeSceneText(engine_context.FrameAllocator(), scene_layer, abs_path);
        const scene_component = scene_layer.GetComponent(SceneComponent).?;
        scene_component.mScenePath.clearAndFree(engine_context.EngineAllocator());
        scene_component.mScenePath.writer(engine_context.EngineAllocator()).write(engine_context.mAssetManager.GetRelPath(abs_path));
    }
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

pub fn GetSceneGroup(self: *SceneManager, frame_allocator: std.mem.Allocator, query: GroupQuery) !std.ArrayList(SceneLayer.Type) {
    const zone = Tracy.ZoneInit("SceneManager::GetSceneGroup", @src());
    defer zone.Deinit();
    return try self.mECSManagerSC.GetGroup(frame_allocator, query);
}

pub fn GetSceneStackIDs(self: *SceneManager, frame_allocator: std.mem.Allocator) !std.ArrayList(SceneLayer.Type) {
    const stack_pos_scenes = try self.mECSManagerSC.GetGroup(frame_allocator, .{ .Component = SceneStackPos });
    std.sort.insertion(SceneLayer.Type, stack_pos_scenes.items, self.mECSManagerSC, SceneManager.SortScenesFunc);
    return stack_pos_scenes;
}

pub fn GetSceneByUUID(self: SceneManager, scene_uuid: u64) ?SceneLayer {
    if (self.mSceneUUIDToWorldID.get(scene_uuid)) |world_id| {
        return SceneLayer{ .mSceneID = world_id, .mECSManagerGORef = &self.mECSManagerGO, .mECSManagerSCRef = &self.mECSManagerSC };
    }
    return null;
}

pub fn SceneECSCallback(self: SceneManager, event: ECSManagerScenes.ECSEventManager.ECSEvent) !void {
    _ = self;
    _ = event;
}
fn SortScenesFunc(ecs_manager_sc: ECSManagerScenes, a: SceneLayer.Type, b: SceneLayer.Type) bool {
    const a_stack_pos_comp = ecs_manager_sc.GetComponent(SceneStackPos, a).?;
    const b_stack_pos_comp = ecs_manager_sc.GetComponent(SceneStackPos, b).?;

    return (b_stack_pos_comp.mPosition < a_stack_pos_comp.mPosition);
}

//===============================ECS MANAGER SC END==============================================

//===============================ECS MANAGER Player==============================================
pub fn CreatePlayer(self: *SceneManager, engine_context: *EngineContext) !Player {
    const new_player = Player{ .mEntityID = try self.mECSManagerPL.CreateEntity(), .mECSManagerRef = &self.mPlayerManager };
    new_player.AddComponent(PossessComponent{});
    new_player.AddComponent(PlayerMic{});
    PlayerUtils.AddLensComponent(engine_context, new_player);
    return new_player;
}
pub fn GetPlayer(self: *SceneManager, player_id: Player.Type) Player {
    return Player{ .mEntityID = player_id, .mECSManagerRef = self.mECSManagerPL };
}
pub fn GetPlayerGroup(self: *SceneManager, frame_allocator: std.mem.Allocator, query: GroupQuery) !std.ArrayList(Player.Type) {
    const zone = Tracy.ZoneInit("SceneManager::GetPlayerGroup", @src());
    defer zone.Deinit();
    return try self.mECSManagerPL.GetGroup(frame_allocator, query);
}
pub fn PlayerECSCallback(self: SceneManager, event: ECSManagerPlayer.ECSEventManager.ECSEvent) !void {
    _ = self;
    _ = event;
}
//===============================ECS MANAGER Player END==============================================

//===============================ECS MANAGER Entity==============================================
pub fn GetEntityByUUID(self: SceneManager, entity_uuid: u64) ?Entity {
    if (self.mEntityUUIDToWorldID.get(entity_uuid)) |world_id| {
        return Entity{ .mEntityID = world_id, .mECSManagerRef = &self.mECSManagerGO };
    }
    return null;
}
pub fn EntityECSCallback(self: *SceneManager, event: ECSManagerGameObj.ECSEventManager.ECSEvent) !void {
    _ = self;
    _ = event;
}
pub fn GetEntityGroup(self: *SceneManager, frame_allocator: std.mem.Allocator, comptime query: GroupQuery) std.ArrayList(Entity.Type) {
    return self.mECSManagerGO.GetGroup(frame_allocator, query);
}
//===============================ECS MANAGER Entity==============================================

pub fn OnViewportResize(self: *SceneManager, frame_allocator: std.mem.Allocator, viewport_width: usize, viewport_height: usize) !void {
    const zone = Tracy.ZoneInit("SceneManager::OnViewportResize", @src());
    defer zone.Deinit();
    self.mViewportWidth = viewport_width;
    self.mViewportHeight = viewport_height;

    const lens_group = try self.mECSManagerPL.GetGroup(frame_allocator, .{ .Component = PlayerLens });
    for (lens_group.items) |player_id| {
        const player = Player{ .mEntityID = player_id, .mECSManagerRef = &self.mECSManagerPL };
        const camera_component = player.GetComponent(PlayerLens).?;
        if (camera_component.mIsFixedAspectRatio == false) {
            camera_component.SetViewportSize(viewport_width, viewport_height);
        }
    }
}

pub fn SaveEntity(self: *SceneManager, frame_allocator: std.mem.Allocator, entity: Entity) !void {
    try self.SaveEntityAs(frame_allocator, entity);
}

pub fn SaveEntityAs(_: *SceneManager, engine_context: *EngineContext, entity: Entity) !void {
    const abs_path = try PlatformUtils.SaveFile(engine_context.FrameAllocator(), ".imfab");
    try engine_context.mSceneSerializer.SerializeEntityText(engine_context.FrameAllocator(), entity, abs_path);
}

pub fn GetEntity(self: *SceneManager, entity_id: Entity.Type) Entity {
    return Entity{ .mEntityID = entity_id, .mECSManagerRef = &self.mECSManagerGO };
}

pub fn GetSceneLayer(self: *SceneManager, scene_id: SceneLayer.Type) SceneLayer {
    return SceneLayer{ .mSceneID = scene_id, .mECSManagerGORef = &self.mECSManagerGO, .mECSManagerSCRef = &self.mECSManagerSC };
}

pub fn RmSceneComp(self: *SceneManager, engine_allocator: std.mem.Allocator, scene_id: SceneLayer.Type, component_ind: ESceneComponents) !void {
    try self.mECSManagerSC.RemoveComponentInd(engine_allocator, scene_id, @intFromEnum(component_ind));
}

pub fn ProcessRemovedObj(self: *SceneManager, engine_context: *EngineContext) !void {
    try self.mECSManagerGO.ProcessEvents(engine_context, .EC_RemoveObj, self, EntityECSCallback);
    try self.mECSManagerSC.ProcessEvents(engine_context, .EC_RemoveObj, self, SceneECSCallback);
    try self.mECSManagerPL.ProcessEvents(engine_context, .EC_RemoveObj, self, PlayerECSCallback);
}

pub fn Copy(self: *SceneManager, engine_context: *EngineContext, other_scene: *SceneManager) !void {
    self.SaveAllScenes(engine_context);
    const frame_allocator = engine_context.FrameAllocator();

    const scene_stack = try self.GetSceneGroup(frame_allocator, .{ .Component = SceneStackPos });
    for (scene_stack.items) |scene_id| {
        const scene = self.GetSceneLayer(scene_id);

        const scene_component = scene.GetComponent(SceneComponent).?;
        const scene_abs_path = try engine_context.mAssetManager.GetAbsPath(frame_allocator, scene_component.mScenePath, .Prj);

        other_scene.LoadScene(engine_context, scene_abs_path);
    }
}

fn InsertScene(self: *SceneManager, frame_allocator: std.mem.Allocator, scene_layer: SceneLayer) !void {
    const scene_component = scene_layer.GetComponent(SceneComponent).?;
    if (scene_component.mLayerType == .GameLayer) {
        _ = try scene_layer.AddComponent(SceneStackPos{ .mPosition = self.mGameLayerInsertIndex });
        const stack_pos_group = try self.mECSManagerSC.GetGroup(frame_allocator, .{ .Component = SceneStackPos });
        for (stack_pos_group.items) |scene_id| {
            const stack_pos = self.mECSManagerSC.GetComponent(SceneStackPos, scene_id).?;
            if (stack_pos.mPosition >= self.mGameLayerInsertIndex) {
                stack_pos.mPosition += 1;
            }
        }
        self.mGameLayerInsertIndex += 1;
    } else {
        _ = try scene_layer.AddComponent(SceneStackPos{ .mPosition = self.mNumofLayers });
    }
    self.mNumofLayers += 1;
}

fn RemoveScene(self: *SceneManager, frame_allocator: std.mem.Allocator, scene_layer: SceneLayer) !void {
    //next realign the scene stack so that everything is in the right position after this one is destroyed
    const destroy_stack_pos = scene_layer.GetComponent(SceneStackPos).?;
    const scene_component = scene_layer.GetComponent(SceneComponent).?;

    var stack_pos_group = try self.mECSManagerSC.GetGroup(frame_allocator, .{ .Component = SceneStackPos });
    defer stack_pos_group.deinit(frame_allocator);

    for (stack_pos_group.items) |pos_scene_id| {
        const stack_pos = self.mECSManagerSC.GetComponent(SceneStackPos, pos_scene_id).?;
        if (stack_pos.mPosition > destroy_stack_pos.mPosition) {
            stack_pos.mPosition -= 1;
        }
    }

    if (scene_component.mLayerType == .GameLayer) {
        self.mGameLayerInsertIndex -= 1;
    }
    self.mNumofLayers -= 1;
}

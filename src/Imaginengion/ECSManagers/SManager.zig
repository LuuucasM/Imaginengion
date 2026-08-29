const std = @import("std");

const Scene = @import("../ECSObjects/Scene.zig");
const LayerType = @import("Components/SceneComponent.zig").LayerType;
const PlatformUtils = @import("../PlatformUtils/PlatformUtils.zig");

const ECSManager = @import("../ECS/ECSManager.zig").ECSManager;
const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;
const Entity = @import("../ECSObjects/Entity.zig");
const ChildType = @import("../ECS/ECSManager.zig").ChildType;

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const EntityComponentsList = EntityComponents.ComponentsList;
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

const SceneComponents = @import("../ECSComponents/SComponents.zig");
const SceneComponentsList = SceneComponents.ComponentsList;
const ESceneComponents = SceneComponents.EComponents;
const SceneComponent = SceneComponents.SceneComponent;
const SceneUUIDComponent = SceneComponents.UUIDComponent;
const SceneNameComponent = SceneComponents.NameComponent;
const SceneStackPos = SceneComponents.StackPosComponent;
//const SceneTransformComponent = SceneComponents.TransformComponent;
const SceneScriptComponent = SceneComponents.ScriptComponent;

const GameContext = @import("../ECSObjects/GameContext.zig");
const GameModeComponentsList = @import("../ECSComponents/GCComponents.zig").ComponentsList;

const Serializer = @import("../Serializer/Serializer.zig");
const ResolveReq = Serializer.ResolveReq;

const AssetComponents = @import("../ECSComponents/AComponents.zig");
const Asset = @import("../ECSObjects/Asset.zig");
const ScriptAsset = AssetComponents.ScriptAsset;
const FileMetaData = AssetComponents.FileMetaData;
const EngineContext = @import("../Core/EngineContext.zig");

const Player = @import("../ECSObjects/Player.zig");
const PlayerComponents = @import("../ECSComponents/PComponents.zig");
const PossessComponent = PlayerComponents.PossessComponent;
const PlayerMic = PlayerComponents.MicComponent;

const Tracy = @import("../Core/Tracy.zig");

const NewSceneConfig = Scene.NewSceneConfig;

const SceneManager = @This();

pub const ECSType = enum {
    GameObj,
    Scenes,
    Players,
    GameModes,
};

pub const ECSManagerS = ECSManager(Scene.Type, &SceneComponentsList);

//scene stuff

mECSManagerSC: ECSManagerS = .empty,

mGameLayerInsertIndex: usize = 0,
mNumofLayers: usize = 0,

mUUIDToWorldID: std.AutoHashMapUnmanaged(u64, usize) = .empty,
mResolveUUIDList: std.ArrayList(ResolveReq) = .empty,

pub fn Init(self: *SceneManager, width: usize, height: usize, engine_allocator: std.mem.Allocator) !void {
    try self.mECSManagerGO.Init(engine_allocator);
    try self.mECSManagerSC.Init(engine_allocator);
    try self.mECSManagerPL.Init(engine_allocator);
    try self.mECSManagerGM.Init(engine_allocator);
}

pub fn Deinit(self: *SceneManager, engine_context: *EngineContext) !void {
    try self.mECSManagerGO.Deinit(engine_context);
    try self.mECSManagerSC.Deinit(engine_context);
    try self.mECSManagerPL.Deinit(engine_context);
    try self.mECSManagerGM.Deinit(engine_context);

    self.mUUIDToWorldID.deinit(engine_context.EngineAllocator());
    self.mResolveUUIDList.deinit(engine_context.EngineAllocator());
}

//===============================ECS MANAGER SC==============================================
pub fn NewScene(self: *SceneManager, engine_context: *EngineContext, _: LayerType, new_scene_config: NewSceneConfig) !Scene {
    var scene_layer = SceneLayer{ .mSceneID = try self.mECSManagerSC.CreateEntity(engine_context.EngineAllocator()), .mSceneManager = self };
    _ = try scene_layer.AddComponent(engine_context, SceneComponent{});

    try scene_layer.CreateSceneConfig(engine_context, new_scene_config);

    try self.InsertScene(engine_context, scene_layer);

    return scene_layer;
}

pub fn DestroyScene(self: *SceneManager, engine_context: *EngineContext, destroy_scene: Scene) !void {
    try self.SaveScene(engine_context, destroy_scene);

    const frame_allocator = engine_context.FrameAllocator();

    //remove all the entities from the scene
    const entity_scene_entities = try destroy_scene.GetEntityGroup(frame_allocator, EntitySceneComponent);

    for (entity_scene_entities.items) |entity_id| {
        self.mECSManagerGO.DestroyEntity(engine_context.EngineAllocator(), entity_id);
    }

    //from from scene stack
    try self.RemoveScene(engine_context.FrameAllocator(), destroy_scene);

    //finally destroy the scene
    try self.mECSManagerSC.DestroyEntity(engine_context.EngineAllocator(), destroy_scene.mSceneID);
}

pub fn LoadScene(self: *SceneManager, engine_context: *EngineContext, abs_path: []const u8) !Scene {
    const scene_layer = try self.NewScene(engine_context, .GameLayer, .{ .bAddSceneName = false, .bAddSceneUUID = false });

    try engine_context.mSerializer.DeserializeScene(engine_context, scene_layer, abs_path, .Text);

    try self.InsertScene(engine_context, scene_layer);

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

pub fn SaveScene(self: *SceneManager, engine_context: *EngineContext, scene_layer: Scene) !void {
    const frame_allocator = engine_context.FrameAllocator();
    const scene_component = scene_layer.GetComponent(SceneComponent).?;

    if (scene_component.mScenePath.items.len != 0) {
        const abs_path = try engine_context.mAssetManager.GetAbsPath(frame_allocator, scene_component.mScenePath.items, .Prj);
        try engine_context.mSerializer.SerializeScene(engine_context, scene_layer, abs_path, .Text);
    } else {
        try self.SaveSceneAs(engine_context, scene_layer);
    }
}

pub fn SaveSceneAs(_: *SceneManager, engine_context: *EngineContext, scene_layer: Scene) !void {
    const abs_path = try PlatformUtils.SaveFile(engine_context.FrameAllocator(), ".imsc");
    if (abs_path.len > 0) {
        try engine_context.mSerializer.SerializeScene(engine_context, scene_layer, abs_path, .Text);
        const scene_component = scene_layer.GetComponent(SceneComponent).?;
        scene_component.mScenePath.clearAndFree(engine_context.EngineAllocator());
        try scene_component.mScenePath.print(engine_context.EngineAllocator(), "{s}", .{engine_context.mAssetManager.GetRelPath(abs_path)});
    }
}

pub fn MoveScene(self: *SceneManager, frame_allocator: std.mem.Allocator, scene_layer: Scene, move_to_pos: usize) !void {
    const scene_component = scene_layer.GetComponent(SceneComponent).?;
    const stack_pos_component = scene_layer.GetComponent(SceneStackPos).?;
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

pub fn GetSceneGroup(self: *SceneManager, frame_allocator: std.mem.Allocator, query: GroupQuery) !std.ArrayList(Scene.Type) {
    const zone = Tracy.ZoneInit("SceneManager::GetSceneGroup", @src());
    defer zone.Deinit();
    return try self.mECSManagerSC.GetGroup(frame_allocator, query);
}

pub fn GetSceneStackIDs(self: *SceneManager, frame_allocator: std.mem.Allocator) !std.ArrayList(Scene.Type) {
    const stack_pos_scenes = try self.mECSManagerSC.GetGroup(frame_allocator, .{ .Component = SceneStackPos });
    std.sort.insertion(Scene.Type, stack_pos_scenes.items, self.mECSManagerSC, SceneManager.SortScenesFunc);
    return stack_pos_scenes;
}

pub fn SceneECSCallback(scene_manager: *anyopaque, _: *EngineContext, event: ECSManagerScenes.ECSEventManager.EventType) anyerror!bool {
    const self: *SceneManager = @ptrCast(@alignCast(scene_manager));

    switch (event) {
        .DestroyEntity => |e| {
            const scene_layer = self.GetSceneLayer(e.mEntityID);
            self.RemoveUUID(scene_layer.GetUUID());
        },
        .RemoveComponent => |e| {
            const scene_layer = self.GetSceneLayer(e.mEntityID);
            if (e.mComponentInd == SceneUUIDComponent.Ind) {
                self.RemoveUUID(scene_layer.GetUUID());
            }
        },
        .Default => @panic("this shouldnt happen\n"),
    }
    return true;
}
pub fn SortScenesFunc(ecs_manager_sc: ECSManagerScenes, a: Scene.Type, b: Scene.Type) bool {
    const a_stack_pos_comp = ecs_manager_sc.GetComponent(SceneStackPos, a).?;
    const b_stack_pos_comp = ecs_manager_sc.GetComponent(SceneStackPos, b).?;

    return (b_stack_pos_comp.mPosition < a_stack_pos_comp.mPosition);
}

//===============================ECS MANAGER SC END==============================================

//===============================ECS MANAGER Player==============================================
pub fn CreatePlayer(self: *SceneManager, engine_context: *EngineContext, new_player_config: Player.NewPlayerConfig) !Player {
    var new_player = Player{ .mEntityID = try self.mECSManagerPL.CreateEntity(engine_context.EngineAllocator()), .mScenemanager = self };
    try new_player.CreatePlayerConfig(engine_context, new_player_config);
    return new_player;
}
pub fn GetPlayer(self: *SceneManager, player_id: Player.Type) Player {
    return Player{ .mEntityID = player_id, .mScenemanager = self };
}
pub fn GetPlayerGroup(self: *SceneManager, frame_allocator: std.mem.Allocator, query: GroupQuery) !std.ArrayList(Player.Type) {
    const zone = Tracy.ZoneInit("SceneManager::GetPlayerGroup", @src());
    defer zone.Deinit();
    return try self.mECSManagerPL.GetGroup(frame_allocator, query);
}
pub fn PlayerECSCallback(scene_manager: *anyopaque, engine_context: *EngineContext, event: ECSManagerPlayers.ECSEventManager.EventType) anyerror!bool {
    const self: *SceneManager = @ptrCast(@alignCast(scene_manager));
    _ = self;
    _ = engine_context;
    _ = event;
    return true;
}
//===============================ECS MANAGER Player END==============================================

//===============================ECS MANAGER Entity==============================================
pub fn EntityECSCallback(scene_manager: *anyopaque, _: *EngineContext, event: ECSManagerEntities.ECSEventManager.EventType) anyerror!bool {
    const self: *SceneManager = @ptrCast(@alignCast(scene_manager));
    switch (event) {
        .DestroyEntity => |e| {
            const entity = self.GetEntity(e.mEntityID);
            self.RemoveUUID(entity.GetUUID());
        },
        .RemoveComponent => |e| {
            const entity = self.GetEntity(e.mEntityID);
            if (e.mComponentInd == EntityUUIDComponent.Ind) {
                self.RemoveUUID(entity.GetUUID());
            }
        },
        .Default => {
            @panic("this musnt happen\n");
        },
    }
    return true;
}

pub fn GetEntityGroup(self: *const SceneManager, frame_allocator: std.mem.Allocator, comptime query: GroupQuery) !std.ArrayList(Entity.Type) {
    return try self.mECSManagerGO.GetGroup(frame_allocator, query);
}
//===============================ECS MANAGER Entity END==============================================

//==================================ECS MANAGER GAME MODE START===========================================
pub fn CreateGameMode(self: *SceneManager, engine_context: *EngineContext, config: GameContext.NewGameModeConfig) !GameContext {
    var new_game_mode = GameMode{ .mEntityID = try self.mECSManagerGM.CreateEntity(engine_context.EngineAllocator()), .mScenemanager = self };
    try new_game_mode.CreateGameModeConfig(engine_context, config);
    return new_game_mode;
}
pub fn GetGameModeGroup(self: *const SceneManager, frame_allocator: std.mem.Allocator, comptime query: GroupQuery) !std.ArrayList(GameContext.Type) {
    return try self.mECSManagerGM.GetGroup(frame_allocator, query);
}
pub fn GetGameMode(self: *SceneManager, gamemode_id: GameContext.Type) GameContext {
    return GameMode{ .mEntityID = gamemode_id, .mScenemanager = self };
}
pub fn GameECSCallback(scene_manager: *anyopaque, engine_context: *EngineContext, event: ECSManagerGameContexts.ECSEventManager.EventType) anyerror!bool {
    _ = scene_manager;
    _ = engine_context;
    _ = event;
    return true;
}
//========================================ECS MANAGER GAME MODE END=========================================

pub fn AddUUID(self: *SceneManager, engine_allocator: std.mem.Allocator, uuid: u64, world_id: usize) !void {
    try self.mUUIDToWorldID.put(engine_allocator, uuid, world_id);
}

pub fn RemoveUUID(self: *SceneManager, uuid: u64) void {
    _ = self.mUUIDToWorldID.remove(uuid);
}

pub fn GetWorldID(self: SceneManager, uuid: u64) ?usize {
    return self.mUUIDToWorldID.get(uuid);
}

pub fn AddResolveUUID(self: *SceneManager, engine_allocator: std.mem.Allocator, resolve_req: ResolveReq) !void {
    try self.mResolveUUIDList.append(engine_allocator, resolve_req);
}

pub fn clearAndFree(self: *SceneManager, engine_context: *EngineContext) !void {
    try self.mECSManagerGO.clearAndFree(engine_context);
    try self.mECSManagerSC.clearAndFree(engine_context);
    try self.mECSManagerPL.clearAndFree(engine_context);

    self.mGameLayerInsertIndex = 0;
    self.mNumofLayers = 0;
}

pub fn SaveEntity(self: *SceneManager, engine_context: *EngineContext, entity: Entity) !void {
    try self.SaveEntityAs(engine_context, entity);
}

pub fn SaveEntityAs(_: *SceneManager, engine_context: *EngineContext, entity: Entity) !void {
    const abs_path = try PlatformUtils.SaveFile(engine_context.FrameAllocator(), ".imfab");
    try engine_context.mSerializer.SerializeEntity(engine_context, entity, abs_path, .Text);
}

pub fn GetEntity(self: *SceneManager, entity_id: Entity.Type) Entity {
    return Entity{ .mEntityID = entity_id, .mSceneManager = self };
}

pub fn GetSceneLayer(self: *SceneManager, scene_id: SceneLayer.Type) SceneLayer {
    return SceneLayer{ .mSceneID = scene_id, .mSceneManager = self };
}

pub fn RmSceneComp(self: *SceneManager, engine_allocator: std.mem.Allocator, scene_id: SceneLayer.Type, component_ind: ESceneComponents) !void {
    try self.mECSManagerSC.RemoveComponentInd(engine_allocator, scene_id, @intFromEnum(component_ind));
}

pub fn ProcessRemovedObj(self: *SceneManager, engine_context: *EngineContext) !void {
    var callback_list: std.DoublyLinkedList = .{};

    var entity_event_callback = ECSManagerGameObj.ECSEventCallback{ .mCtx = self, .mCallbackFn = EntityECSCallback };
    callback_list.append(&entity_event_callback.mNode);
    try self.mECSManagerGO.ProcessEvents(engine_context, .Remove, callback_list);
    //sett first and last to null to reset for scenes
    callback_list.first = null;
    callback_list.last = null;

    var scene_event_callback = ECSManagerScenes.ECSEventCallback{ .mCtx = self, .mCallbackFn = SceneECSCallback };
    callback_list.append(&scene_event_callback.mNode);
    try self.mECSManagerSC.ProcessEvents(engine_context, .Remove, callback_list);
    //reset for players
    callback_list.first = null;
    callback_list.last = null;

    var player_event_callback = ECSManagerPlayer.ECSEventCallback{ .mCtx = self, .mCallbackFn = PlayerECSCallback };
    callback_list.append(&player_event_callback.mNode);
    try self.mECSManagerPL.ProcessEvents(engine_context, .Remove, callback_list);
    callback_list.first = null;
    callback_list.last = null;

    var game_event_callback = ECSManagerGameMode.ECSEventCallback{ .mCtx = self, .mCallbackFn = GameECSCallback };
    callback_list.append(&game_event_callback.mNode);
    try self.mECSManagerGM.ProcessEvents(engine_context, .Remove, callback_list);
}

pub fn Copy(self: *SceneManager, engine_context: *EngineContext, other_scene: *SceneManager) !void {
    try self.Serialize(engine_context);
    const frame_allocator = engine_context.FrameAllocator();

    const scene_stack = try self.GetSceneGroup(frame_allocator, .{ .Component = SceneStackPos });
    for (scene_stack.items) |scene_id| {
        const scene = self.GetSceneLayer(scene_id);

        const scene_component = scene.GetComponent(SceneComponent).?;
        const scene_abs_path = try engine_context.mAssetManager.GetAbsPath(frame_allocator, scene_component.mScenePath.items, .Prj);

        _ = try other_scene.LoadScene(engine_context, scene_abs_path);
    }
}

fn InsertScene(self: *SceneManager, engine_context: *EngineContext, scene_layer: SceneLayer) !void {
    const scene_component = scene_layer.GetComponent(SceneComponent).?;
    if (scene_component.mLayerType == .GameLayer) {
        _ = try scene_layer.AddComponent(engine_context, SceneStackPos{ .mPosition = self.mGameLayerInsertIndex });
        const stack_pos_group = try self.mECSManagerSC.GetGroup(engine_context.FrameAllocator(), .{ .Component = SceneStackPos });
        for (stack_pos_group.items) |scene_id| {
            const stack_pos = self.mECSManagerSC.GetComponent(SceneStackPos, scene_id).?;
            if (stack_pos.mPosition >= self.mGameLayerInsertIndex) {
                stack_pos.mPosition += 1;
            }
        }
        self.mGameLayerInsertIndex += 1;
    } else {
        _ = try scene_layer.AddComponent(engine_context, SceneStackPos{ .mPosition = self.mNumofLayers });
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

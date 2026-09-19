const std = @import("std");

const Scene = @import("../ECSObjects/Scene.zig");
const LayerType = @import("Components/SceneComponent.zig").LayerType;
const PlatformUtils = @import("../PlatformUtils/PlatformUtils.zig");

const ECSManager = @import("../ECS/ECSManager.zig").ECSManager;
const EventManager = @import("../Events/EventManager.zig");
const EventResult = EventManager.EventResult;
const EventData = @import("../Events/SManagerData.zig");

const ResolveReq = @import("../Serializer/Serializer.zig").ResolveReq;

const EngineContext = @import("../Core/EngineContext.zig");

const WorldManager = @import("../Core/WorldManager.zig");

const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;
const ECSCore = @import("ECSManager.zig").Core;

const SceneComponents = @import("../ECSComponents/SComponents.zig");
const SceneComponentsList = SceneComponents.ComponentsList;
const SceneComponent = SceneComponents.SceneComponent;
const UUIDComponent = SceneComponents.UUIDComponent;
const NameComponent = SceneComponents.NameComponent;
const SceneStackPos = SceneComponents.StackPosComponent;
//const SceneTransformComponent = SceneComponents.TransformComponent;
const SceneScriptComponent = SceneComponents.ScriptComponent;

const Entity = @import("../ECSObjects/Entity.zig");
const EComponents = @import("../ECSComponents/EComponents.zig");
const EntitySceneComponent = EComponents.EntitySceneComponent;

pub const EventManagerT = EventManager.EventManager(EventData);

const Tracy = @import("../Core/Tracy.zig");

const NewSceneConfig = Scene.NewSceneConfig;

const SManager = @This();

const Core = ECSCore(SManager);

pub const ECSType = enum {
    GameObj,
    Scenes,
    Players,
    GameModes,
};

pub const ECSManagerS = ECSManager(Scene.Type, &SceneComponentsList);

//scene stuff
pub const uninit: SManager = .{
    .mECSManager = .empty,
    .mGameLayerInsertIndex = 0,
    .mNumofLayers = 0,
    .mUUIDToWorldID = .empty,
    .mResolveUUIDList = .empty,
};

mECSManager: ECSManagerS,
mEventManager: EventManagerT,

mUUIDToWorldID: std.AutoHashMapUnmanaged(u64, usize),
mResolveUUIDList: std.ArrayList(ResolveReq),

mGameLayerInsertIndex: usize,
mNumofLayers: usize,

pub const Init = Core.Init;

pub const Deinit = Core.Deinit;

pub fn CreateScene(self: *SManager, engine_context: *EngineContext, layer_type: LayerType, config: Scene.CreateConfig) !Scene {
    const new_scene: Scene = try Core.CreateObj(self, engine_context, config);
    self.GetSceneComponent(new_scene.mID).mLayerType = layer_type;
    try self.InsertScene(engine_context, new_scene);
    return new_scene;
}

pub const DeleteScene = Core.DeleteObj;

pub const Duplicate = Core.Duplicate;

pub const CreateChild = Core.CreateChild;

pub const AddComponent = Core.AddComponent;

pub const AddResolveUUID = Core.AddResolveUUID;

pub const AddUUID = Core.AddUUID;

pub fn clearAndFree(self: *SManager, engine_context: *EngineContext) void {
    Core.clearAndFree(self, engine_context);
    self.mGameLayerInsertIndex = 0;
    self.mNumofLayers = 0;
}

pub const GetComponent = Core.GetComponent;

pub const GetGroup = Core.GetGroup;

pub const GetWorldID = Core.GetWorldID;

pub const HasComponent = Core.HasComponent;

pub const IsActiveObj = Core.IsActiveObj;

pub const RemoveUUID = Core.RemoveUUID;

pub const SaveScene = Core.SaveObject;

pub const SaveSceneAs = Core.SaveObjectAs;

pub const LoadScene = Core.LoadObject;

pub fn GetSceneComponent(self: *SManager, scene_id: Scene.Type) SceneComponent {
    return self.mECSManager.GetComponent(SceneComponent, scene_id);
}

pub fn ProcessEvents(self: *SManager, comptime event_data: type, comptime event_category: event_data.EventCategories, engine_context: *EngineContext, callback_list: std.DoublyLinkedList) !void {
    if (event_data == EventData) {
        const callback = EventManagerT.EventCallback{
            .mCtx = self,
            .mCallbackFn = struct {
                fn thunk(ctx: *anyopaque, ec: *EngineContext, event: *const event_data.EventT) anyerror!EventResult {
                    return @as(SManager, @ptrCast(@alignCast(ctx))).OnManagerEvents(ec, event.*);
                }
            }.thunk,
        };
        callback_list.append(&callback.mNode);
        self.mEventManager.ProcessCategory(event_category, engine_context, callback_list);
    } else {
        std.log.err("SManager.ProcessEvents does not currently handle processing events of type {s}", @typeName(event_data));
    }
}

pub fn OnManagerEvents(self: *SManager, engine_context: *EngineContext, event: EventData.EventT) anyerror!EventResult {
    switch (event) {
        .ToDestroyScene => |destroy_event| {
            const scene = destroy_event.Scene;
            const scene_entities = try scene.GetEntityGroup(engine_context.FrameAllocator(), EntitySceneComponent);

            for (scene_entities) |entity_id| {
                const e: Entity = .{ .mID = entity_id, .mManager = scene.mManager };
                e.Delete(engine_context);
            }

            self.RemoveScene(engine_context.FrameAllocator(), scene);
            self.mECSManager.DestroyEntity(engine_context, scene.mID);
        },
        .Default => unreachable,
    }
}

pub fn MoveScene(self: *SManager, frame_allocator: std.mem.Allocator, scene_layer: Scene, move_to_pos: usize) !void {
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

pub fn GetSceneStackIDs(self: *SManager, frame_allocator: std.mem.Allocator) !std.ArrayList(Scene.Type) {
    const stack_pos_scenes = try self.mECSManagerSC.GetGroup(frame_allocator, .{ .Component = SceneStackPos });
    std.sort.insertion(Scene.Type, stack_pos_scenes.items, self.mECSManagerSC, SManager.SortScenesFunc);
    return stack_pos_scenes;
}

pub fn SortScenesFunc(ecs_manager_sc: ECSManagerS, a: Scene.Type, b: Scene.Type) bool {
    const a_stack_pos_comp = ecs_manager_sc.GetComponent(SceneStackPos, a).?;
    const b_stack_pos_comp = ecs_manager_sc.GetComponent(SceneStackPos, b).?;

    return (b_stack_pos_comp.mPosition < a_stack_pos_comp.mPosition);
}

fn InsertScene(self: *SManager, engine_context: *EngineContext, scene_layer: Scene) !void {
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

fn RemoveScene(self: *SManager, frame_allocator: std.mem.Allocator, scene_layer: Scene) !void {
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

pub fn ApplyConfig(self: *SManager, engine_context: *EngineContext, player_id: Scene.Type, config: Scene.CreateConfig) !void {
    if (config.bAddName) {
        const name_component: NameComponent = .empty;
        try name_component.mName.appendSlice(engine_context.EngineAllocator(), "New Entity");
        self.AddComponent(engine_context, player_id, name_component);
    }
    if (config.bAddUUID) {
        const io_source = std.Random.IoSource{ .io = engine_context.Io() };
        const new_random = io_source.interface();
        const new_uuid_component = try self.AddComponent(engine_context, player_id, UUIDComponent{ .ID = new_random.int(u64) });
        try self.AddUUID(engine_context.EngineAllocator(), new_uuid_component.ID, player_id);
    }
}

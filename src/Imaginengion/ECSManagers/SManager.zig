const std = @import("std");

const Scene = @import("../ECSObjects/Scene.zig");
const LayerType = @import("../ECSComponents/Scene/SceneComponent.zig").LayerType;
const PlatformUtils = @import("../PlatformUtils/PlatformUtils.zig");

const ECSManager = @import("../ECS/ECSManager.zig").ECSManager;
const EventManager = @import("../Events/EventManager.zig");
const EventResult = EventManager.EventResult;
const EventData = @import("../Events/SManagerData.zig");
const ECSEventData = @import("../Events/ECSEventData.zig");

const EngineContext = @import("../Core/EngineContext.zig");

const WorldManager = @import("../Core/WorldManager.zig");

const GroupQuery = @import("../ECS/ECSManager.zig").GroupQuery;
const ECSCore = @import("Manager.zig").Core;

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
const EntityChildComponent = @import("../ECS/Components.zig").ChildComponent(Entity.Type);

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

pub const ECSManagerT = ECSManager(Scene.Type, &SceneComponentsList, "SceneECS");

//scene stuff
pub const empty: SManager = .{
    .mECSManager = .empty,
    .mEventManager = .empty,
    .mGameLayerInsertIndex = 0,
    .mNumofLayers = 0,
    .mUUIDToWorldID = .empty,
};

mECSManager: ECSManagerT,
mEventManager: EventManagerT,

mUUIDToWorldID: std.AutoHashMapUnmanaged(u64, Scene.Type),

mGameLayerInsertIndex: usize,
mNumofLayers: usize,

pub const Init = Core.Init;

pub const SetSyncCallback = Core.SetSyncCallback;

pub const Deinit = Core.Deinit;

pub fn CreateScene(self: *SManager, engine_context: *EngineContext, layer_type: LayerType, config: Scene.CreateConfig) !Scene {
    const new_scene: Scene = try Core.CreateObj(self, engine_context, config);
    //nothing else adds this, and the stack bookkeeping below reads it
    _ = try new_scene.AddComponent(engine_context, SceneComponent{ .mLayerType = layer_type });
    try self.InsertScene(engine_context, new_scene);
    return new_scene;
}

/// A scene with no components that is not in the scene stack yet, for scenes whose components all come from
/// a file: the file's SceneComponent slots it into the stack (SceneComponent.PostParse)
pub fn CreateBlankScene(self: *SManager, engine_context: *EngineContext) !Scene {
    return try Core.CreateObj(self, engine_context, Scene.BlankConfig);
}

pub const DeleteScene = Core.DeleteObj;

pub const Duplicate = Core.Duplicate;

pub const CreateChild = Core.CreateChild;

pub const AddComponent = Core.AddComponent;

pub const AddUUID = Core.AddUUID;

pub fn clearAndFree(self: *SManager, engine_context: *EngineContext) void {
    Core.clearAndFree(self, engine_context);
    self.mGameLayerInsertIndex = 0;
    self.mNumofLayers = 0;
}

pub const GetComponent = Core.GetComponent;

pub const RemoveComponent = Core.RemoveComponent;
pub const RemoveComponentSync = Core.RemoveComponentSync;

pub const GetGroup = Core.GetGroup;

pub const GetWorldID = Core.GetWorldID;

pub const HasComponent = Core.HasComponent;

pub const IsActiveObj = Core.IsActiveObj;

pub const RemoveUUID = Core.RemoveUUID;

pub const SaveScene = Core.SaveObject;

pub const SaveSceneAs = Core.SaveObjectAs;

pub const LoadScene = Core.LoadObject;

pub fn Copy(self: *SManager, engine_context: *EngineContext, other: *SManager) !void {
    try Core.Copy(self, engine_context, other);
    other.mNumofLayers = self.mNumofLayers;
    other.mGameLayerInsertIndex = self.mGameLayerInsertIndex;
}

pub fn GetSceneComponent(self: *SManager, scene_id: Scene.Type) *SceneComponent {
    return self.mECSManager.GetComponent(SceneComponent, scene_id).?;
}

pub fn ProcessEvents(self: *SManager, comptime event_data: type, comptime event_category: event_data.EventCategories, engine_context: *EngineContext, callback_list: *std.DoublyLinkedList) !void {
    if (event_data == EventData) {
        var callback = EventManagerT.EventCallback{
            .mCtx = self,
            .mCallbackFn = struct {
                fn thunk(ctx: *anyopaque, ec: *EngineContext, event: *const event_data.EventT) anyerror!EventResult {
                    return @as(*SManager, @ptrCast(@alignCast(ctx))).OnManagerEvents(ec, event.*);
                }
            }.thunk,
        };
        //the list belongs to the caller, so ours comes off again on the way out
        callback_list.append(&callback.mNode);
        defer callback_list.remove(&callback.mNode);
        try self.mEventManager.ProcessCategory(event_category, engine_context, callback_list.*);
        self.mEventManager.ClearCategory(engine_context.EngineAllocator(), event_category, .ClearRetainingCapacity);
    } else if (event_data == ECSEventData) {
        var uuid_callback = ECSManagerT.ECSEventCallback{ .mCtx = self, .mCallbackFn = Core.RemoveDestroyedUUID };
        callback_list.append(&uuid_callback.mNode);
        defer callback_list.remove(&uuid_callback.mNode);
        try self.mECSManager.ProcessEvents(engine_context, event_category, callback_list);
    } else {
        std.log.err("SManager.ProcessEvents does not currently handle processing events of type {s}", .{@typeName(event_data)});
    }
}

pub fn OnManagerEvents(self: *SManager, engine_context: *EngineContext, event: EventData.EventT) anyerror!EventResult {
    switch (event) {
        .ToDestroyScene => |destroy_event| {
            const scene = destroy_event.Scene;

            //the scene's entities are not its ECS children, they point at it through EntitySceneComponent.
            //only the top level ones are deleted here, the ECS takes everything below them along
            const EntitySceneQuery = GroupQuery{ .Component = EntitySceneComponent };
            const EntityChildQuery = GroupQuery{ .Component = EntityChildComponent };
            const root_entities = try scene.GetEntityGroup(engine_context.FrameAllocator(), .{
                .Not = .{
                    .mFirst = &EntitySceneQuery,
                    .mSecond = &EntityChildQuery,
                },
            });
            for (root_entities.items) |entity_id| {
                try scene.GetEntity(entity_id).Delete(engine_context);
            }

            //while the scene still has its stack position to close the gap with
            try self.RemoveScene(engine_context.FrameAllocator(), scene);
            try self.mECSManager.DestroyEntity(engine_context, scene.mID);
        },
        .Default => unreachable,
    }
    return .Continue;
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
        const scene_stack_pos_list = try self.mECSManager.GetGroup(frame_allocator, .{ .Component = SceneStackPos });

        for (scene_stack_pos_list.items) |list_scene_id| {
            const scene_stack_pos_component = self.mECSManager.GetComponent(SceneStackPos, list_scene_id).?;
            if (scene_stack_pos_component.mPosition >= new_pos and scene_stack_pos_component.mPosition < current_pos) {
                scene_stack_pos_component.mPosition += 1;
            }
        }
    } else {
        //we are moving the scene up in position so we need to move everything between current_pos and new_pos down 1 position
        const scene_stack_pos_list = try self.mECSManager.GetGroup(frame_allocator, .{ .Component = SceneStackPos });

        for (scene_stack_pos_list.items) |list_scene_id| {
            const scene_stack_pos_component = self.mECSManager.GetComponent(SceneStackPos, list_scene_id).?;
            if (scene_stack_pos_component.mPosition > current_pos and scene_stack_pos_component.mPosition <= new_pos) {
                scene_stack_pos_component.mPosition -= 1;
            }
        }
    }

    stack_pos_component.mPosition = new_pos;
}

/// Scenes ordered for display: highest stack position first, so the topmost layer
/// renders at the top of the list.
pub fn GetSceneStackIDs(self: *SManager, frame_allocator: std.mem.Allocator) !std.ArrayList(Scene.Type) {
    const stack_pos_scenes = try self.mECSManager.GetGroup(frame_allocator, .{ .Component = SceneStackPos });
    std.sort.insertion(Scene.Type, stack_pos_scenes.items, &self.mECSManager, SManager.SortScenesFunc);
    return stack_pos_scenes;
}

pub fn SortScenesFunc(ecs_manager_sc: *ECSManagerT, a: Scene.Type, b: Scene.Type) bool {
    const a_stack_pos_comp = ecs_manager_sc.GetComponent(SceneStackPos, a).?;
    const b_stack_pos_comp = ecs_manager_sc.GetComponent(SceneStackPos, b).?;

    return (b_stack_pos_comp.mPosition < a_stack_pos_comp.mPosition);
}

/// Gives the scene its stack position from its SceneComponent's layer type
pub fn InsertScene(self: *SManager, engine_context: *EngineContext, scene_layer: Scene) !void {
    const scene_component = scene_layer.GetComponent(SceneComponent).?;
    if (scene_component.mLayerType == .GameLayer) {
        //shift the overlays up before adding, otherwise the new scene is in the group too
        //and shifts itself past the slot it was just given
        const stack_pos_group = try self.mECSManager.GetGroup(engine_context.FrameAllocator(), .{ .Component = SceneStackPos });
        for (stack_pos_group.items) |scene_id| {
            const stack_pos = self.mECSManager.GetComponent(SceneStackPos, scene_id).?;
            if (stack_pos.mPosition >= self.mGameLayerInsertIndex) {
                stack_pos.mPosition += 1;
            }
        }
        _ = try scene_layer.AddComponent(engine_context, SceneStackPos{ .mPosition = self.mGameLayerInsertIndex });
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

    var stack_pos_group = try self.mECSManager.GetGroup(frame_allocator, .{ .Component = SceneStackPos });
    defer stack_pos_group.deinit(frame_allocator);

    for (stack_pos_group.items) |pos_scene_id| {
        const stack_pos = self.mECSManager.GetComponent(SceneStackPos, pos_scene_id).?;
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
    if (config.bAddSceneName) {
        var name_component: NameComponent = .empty;
        try name_component.mName.appendSlice(engine_context.EngineAllocator(), "New Scene");
        _ = try self.AddComponent(engine_context, player_id, name_component);
    }
    if (config.bAddSceneUUID) {
        const io_source = std.Random.IoSource{ .io = engine_context.Io() };
        const new_random = io_source.interface();
        const new_uuid_component = try self.AddComponent(engine_context, player_id, UUIDComponent{ .ID = new_random.int(u64) });
        try self.AddUUID(engine_context.EngineAllocator(), new_uuid_component.ID, player_id);
    }
}

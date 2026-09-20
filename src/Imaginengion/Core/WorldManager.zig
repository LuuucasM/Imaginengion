const WorldManager = @This();

const std = @import("std");

const EngineContext = @import("EngineContext.zig");
const GroupQuery = @import("../ECS/ECSManager.zig").GroupQuery;
const LayerType = @import("../ECSComponents/Scene/SceneComponent.zig").LayerType;
const ESceneComponents = @import("../ECSComponents/SComponents.zig").EComponents;

const Entity = @import("../ECSObjects/Entity.zig");
const GameContext = @import("../ECSObjects/GameContext.zig");
const Player = @import("../ECSObjects/Player.zig");
const Scene = @import("../ECSObjects/Scene.zig");

const EManager = @import("../ECSManagers/EManager.zig");
const GCManager = @import("../ECSManagers/GCManager.zig");
const PManager = @import("../ECSManagers/PManager.zig");
const SManager = @import("../ECSManagers/SManager.zig");

const EEventData = @import("../Events/EManagerData.zig");
const GCEventData = @import("../Events/GCManagerData.zig");
const PEventData = @import("../Events/PManagerData.zig");
const SEventData = @import("../Events/SManagerData.zig");
const ECSEventData = @import("../Events/ECSEventData.zig");

const ClearAndFreeOptions = enum {
    EManager,
    GCManager,
    PManager,
    SManager,
};

mEManager: EManager = .empty,
mGCManager: GCManager = .empty,
mPManager: PManager = .empty,
mSManager: SManager = .empty,

pub fn GetEntity(self: *WorldManager, entity_id: Entity.Type) Entity {
    return Entity{ .mID = entity_id, .mManager = self };
}

pub fn GetGameContext(self: *WorldManager, gamecontext_id: GameContext.Type) GameContext {
    return GameContext{ .mID = gamecontext_id, .mManager = self };
}

pub fn GetPlayer(self: *WorldManager, player_id: Player.Type) Player {
    return Player{ .mID = player_id, .mManager = self };
}

pub fn GetScene(self: *WorldManager, scene_id: Scene.Type) Scene {
    return Scene{ .mID = scene_id, .mManager = self };
}

pub fn Init(self: *WorldManager, engine_allocator: std.mem.Allocator) !void {
    self.mEManager.Init(engine_allocator);
    self.mGCManager.Init(engine_allocator);
    self.mPManager.Init(engine_allocator);
    self.mSManager.Init(engine_allocator);
}

pub fn Deinit(self: *WorldManager, engine_context: *EngineContext) void {
    self.mEManager.Deinit(engine_context);
    self.mGCManager.Deinit(engine_context);
    self.mPManager.Deinit(engine_context);
    self.mSManager.Deinit(engine_context);
}

pub fn clearAndFree(self: *WorldManager, engine_context: *EngineContext, options: ClearAndFreeOptions) !void {
    switch (options) {
        .EManager => try self.mEManager.clearAndFree(engine_context),
        .GCManager => try self.mGCManager.clearAndFree(engine_context),
        .PManager => try self.mPManager.clearAndFree(engine_context),
        .SManager => try self.mSManager.clearAndFree(engine_context),
    }
}

pub fn Copy(self: *WorldManager, engine_context: *EngineContext, other_world: *WorldManager) !void {
    self.mEManager.Copy(engine_context, other_world.mEManager);
    self.mGCManager.Copy(engine_context, other_world.mEManager);
    self.mPManager.Copy(engine_context, other_world.mEManager);
    self.mSManager.Copy(engine_context, other_world.mEManager);
}

pub fn ProcessEvents(self: *WorldManager, comptime event_data: type, comptime event_category: event_data.EventCategories, engine_context: *EngineContext, callback_list: std.DoublyLinkedList) !void {
    if (event_data == EEventData) {
        self.mEManager.ProcessEvents(event_data, event_category, engine_context, callback_list);
    } else if (event_data == GCEventData) {
        self.mGCManager.ProcessEvents(event_data, event_category, engine_context, callback_list);
    } else if (event_data == PEventData) {
        self.mPManager.ProcessEvents(event_data, event_category, engine_context, callback_list);
    } else if (event_data == SEventData) {
        self.mSManager.ProcessEvents(event_data, event_category, engine_context, callback_list);
    } else if (event_data == ECSEventData) {
        self.mEManager.ProcessEvents(event_data, event_category, engine_context, callback_list);
        self.mGCManager.ProcessEvents(event_data, event_category, engine_context, callback_list);
        self.mPManager.ProcessEvents(event_data, event_category, engine_context, callback_list);
        self.mSManager.ProcessEvents(event_data, event_category, engine_context, callback_list);
    } else {
        std.log.err("EManager.ProcessEvents does not currently handle processing events of type {s}", @typeName(event_data));
    }
}

//===============================Scenes==============================================
pub fn NewScene(self: *WorldManager, engine_context: *EngineContext, layer_type: LayerType, config: Scene.CreateConfig) !Scene {
    return try self.mSManager.CreateScene(engine_context, layer_type, config);
}

pub fn DestroyScene(self: *WorldManager, engine_context: *EngineContext, destroy_scene: Scene) !void {
    self.mSManager.DeleteScene(engine_context, destroy_scene.mID);
}

pub fn LoadScene(self: *WorldManager, engine_context: *EngineContext, abs_path: []const u8) !Scene {
    self.mSManager.LoadScene(engine_context, abs_path);
}

pub fn SaveScene(self: *WorldManager, engine_context: *EngineContext, scene: Scene) !void {
    self.mSManager.SaveScene(engine_context, scene);
}

pub fn SaveSceneAs(self: *WorldManager, engine_context: *EngineContext, scene: Scene) !void {
    self.mSManager.SaveSceneAs(engine_context, scene);
}

pub fn MoveScene(self: *WorldManager, frame_allocator: std.mem.Allocator, scene: Scene, move_to_pos: usize) !void {
    self.mSManager.MoveScene(frame_allocator, scene, move_to_pos);
}

pub fn GetSceneGroup(self: *WorldManager, frame_allocator: std.mem.Allocator, query: GroupQuery) !std.ArrayList(Scene.Type) {
    self.mSManager.GetGroup(frame_allocator, query);
}

pub fn GetSceneStackIDs(self: *WorldManager, frame_allocator: std.mem.Allocator) !std.ArrayList(Scene.Type) {
    self.mSManager.GetSceneStackIDs(frame_allocator);
}

pub fn RmSceneComp(self: *WorldManager, engine_allocator: std.mem.Allocator, scene_id: Scene.Type, component_ind: ESceneComponents) !void {
    self.mSManager.
}

pub fn SceneECSCallback(world_manager: *anyopaque, engine_context: *EngineContext, event: SManager.EventManagerT.EventType) anyerror!bool {
    _ = .{ world_manager, engine_context, event };
    @panic("WorldManager.SceneECSCallback not implemented");
}

fn InsertScene(self: *WorldManager, engine_context: *EngineContext, scene: Scene) !void {
    _ = .{ self, engine_context, scene };
    @panic("WorldManager.InsertScene not implemented");
}

fn RemoveScene(self: *WorldManager, frame_allocator: std.mem.Allocator, scene: Scene) !void {
    _ = .{ self, frame_allocator, scene };
    @panic("WorldManager.RemoveScene not implemented");
}

//===============================Entities==============================================
pub fn GetEntityGroup(self: *const WorldManager, frame_allocator: std.mem.Allocator, comptime query: GroupQuery) !std.ArrayList(Entity.Type) {
    _ = .{ self, frame_allocator, query };
    @panic("WorldManager.GetEntityGroup not implemented");
}

pub fn SaveEntity(self: *WorldManager, engine_context: *EngineContext, entity: Entity) !void {
    _ = .{ self, engine_context, entity };
    @panic("WorldManager.SaveEntity not implemented");
}

pub fn SaveEntityAs(self: *WorldManager, engine_context: *EngineContext, entity: Entity) !void {
    _ = .{ self, engine_context, entity };
    @panic("WorldManager.SaveEntityAs not implemented");
}

pub fn EntityECSCallback(world_manager: *anyopaque, engine_context: *EngineContext, event: EManager.EventManagerT.EventType) anyerror!bool {
    _ = .{ world_manager, engine_context, event };
    @panic("WorldManager.EntityECSCallback not implemented");
}

//===============================Players==============================================
pub fn CreatePlayer(self: *WorldManager, engine_context: *EngineContext, config: Player.CreateConfig) !Player {
    _ = .{ self, engine_context, config };
    @panic("WorldManager.CreatePlayer not implemented");
}

pub fn GetPlayerGroup(self: *WorldManager, frame_allocator: std.mem.Allocator, query: GroupQuery) !std.ArrayList(Player.Type) {
    _ = .{ self, frame_allocator, query };
    @panic("WorldManager.GetPlayerGroup not implemented");
}

pub fn PlayerECSCallback(world_manager: *anyopaque, engine_context: *EngineContext, event: PManager.EventManagerT.EventType) anyerror!bool {
    _ = .{ world_manager, engine_context, event };
    @panic("WorldManager.PlayerECSCallback not implemented");
}

//===============================Game Contexts (formerly GameModes)==============================================
pub fn CreateGameContext(self: *WorldManager, engine_context: *EngineContext, config: GameContext.CreateConfig) !GameContext {
    _ = .{ self, engine_context, config };
    @panic("WorldManager.CreateGameContext not implemented");
}

pub fn GetGameContextGroup(self: *const WorldManager, frame_allocator: std.mem.Allocator, comptime query: GroupQuery) !std.ArrayList(GameContext.Type) {
    _ = .{ self, frame_allocator, query };
    @panic("WorldManager.GetGameContextGroup not implemented");
}

pub fn GameContextECSCallback(world_manager: *anyopaque, engine_context: *EngineContext, event: GCManager.EventManagerT.EventType) anyerror!bool {
    _ = .{ world_manager, engine_context, event };
    @panic("WorldManager.GameContextECSCallback not implemented");
}

//===============================UUIDs==============================================
//each manager owns the UUID -> ID map for its own object type, these just route to the right one

/// Returns the object with the given UUID, or null if no object of that type with that UUID is loaded
pub fn GetObjectByUUID(self: *WorldManager, comptime obj_t: type, uuid: u64) ?obj_t {
    const obj_id = self.GetManager(obj_t).GetWorldID(uuid) orelse return null;
    return .{ .mID = obj_id, .mManager = self };
}

/// Returns the manager that owns objects of type obj_t (Entity -> EManager, Scene -> SManager, ...)
pub fn GetManager(self: *WorldManager, comptime obj_t: type) *ManagerT(obj_t) {
    if (obj_t == Entity) {
        return &self.mEManager;
    } else if (obj_t == GameContext) {
        return &self.mGCManager;
    } else if (obj_t == Player) {
        return &self.mPManager;
    } else if (obj_t == Scene) {
        return &self.mSManager;
    } else {
        @compileError(std.fmt.comptimePrint("{s} is not an object type owned by the WorldManager", .{@typeName(obj_t)}));
    }
}

pub fn ManagerT(comptime obj_t: type) type {
    if (obj_t == Entity) {
        return EManager;
    } else if (obj_t == GameContext) {
        return GCManager;
    } else if (obj_t == Player) {
        return PManager;
    } else if (obj_t == Scene) {
        return SManager;
    } else {
        @compileError(std.fmt.comptimePrint("{s} is not an object type owned by the WorldManager", .{@typeName(obj_t)}));
    }
}

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
        .EManager => self.mEManager.clearAndFree(engine_context),
        .GCManager => self.mGCManager.clearAndFree(engine_context),
        .PManager => self.mPManager.clearAndFree(engine_context),
        .SManager => self.mSManager.clearAndFree(engine_context),
    }
}

pub fn Copy(self: *WorldManager, engine_context: *EngineContext, other_world: *WorldManager) !void {
    _ = .{ self, engine_context, other_world };
    @panic("WorldManager.Copy not implemented");
}

pub fn Serialize(self: *WorldManager, engine_context: *EngineContext) !void {
    _ = .{ self, engine_context };
    @panic("WorldManager.Serialize not implemented");
}

pub fn ProcessRemovedObj(self: *WorldManager, engine_context: *EngineContext) !void {
    _ = .{ self, engine_context };
    @panic("WorldManager.ProcessRemovedObj not implemented");
}

//===============================Scenes==============================================
pub fn NewScene(self: *WorldManager, engine_context: *EngineContext, layer_type: LayerType, config: Scene.CreateConfig) !Scene {
    _ = .{ self, engine_context, layer_type, config };
    @panic("WorldManager.NewScene not implemented");
}

pub fn DestroyScene(self: *WorldManager, engine_context: *EngineContext, destroy_scene: Scene) !void {
    _ = .{ self, engine_context, destroy_scene };
    @panic("WorldManager.DestroyScene not implemented");
}

pub fn LoadScene(self: *WorldManager, engine_context: *EngineContext, abs_path: []const u8) !Scene {
    _ = .{ self, engine_context, abs_path };
    @panic("WorldManager.LoadScene not implemented");
}

pub fn SaveScene(self: *WorldManager, engine_context: *EngineContext, scene: Scene) !void {
    _ = .{ self, engine_context, scene };
    @panic("WorldManager.SaveScene not implemented");
}

pub fn SaveSceneAs(self: *WorldManager, engine_context: *EngineContext, scene: Scene) !void {
    _ = .{ self, engine_context, scene };
    @panic("WorldManager.SaveSceneAs not implemented");
}

pub fn MoveScene(self: *WorldManager, frame_allocator: std.mem.Allocator, scene: Scene, move_to_pos: usize) !void {
    _ = .{ self, frame_allocator, scene, move_to_pos };
    @panic("WorldManager.MoveScene not implemented");
}

pub fn GetSceneGroup(self: *WorldManager, frame_allocator: std.mem.Allocator, query: GroupQuery) !std.ArrayList(Scene.Type) {
    _ = .{ self, frame_allocator, query };
    @panic("WorldManager.GetSceneGroup not implemented");
}

pub fn GetSceneStackIDs(self: *WorldManager, frame_allocator: std.mem.Allocator) !std.ArrayList(Scene.Type) {
    _ = .{ self, frame_allocator };
    @panic("WorldManager.GetSceneStackIDs not implemented");
}

pub fn SortScenesFunc(s_manager: SManager, a: Scene.Type, b: Scene.Type) bool {
    _ = .{ s_manager, a, b };
    @panic("WorldManager.SortScenesFunc not implemented");
}

pub fn RmSceneComp(self: *WorldManager, engine_allocator: std.mem.Allocator, scene_id: Scene.Type, component_ind: ESceneComponents) !void {
    _ = .{ self, engine_allocator, scene_id, component_ind };
    @panic("WorldManager.RmSceneComp not implemented");
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

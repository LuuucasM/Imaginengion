const WorldManager = @This();

const std = @import("std");

const EngineContext = @import("EngineContext.zig");
const GroupQuery = @import("../ECS/ECSManager.zig").GroupQuery;
const ResolveReq = @import("../Serializer/Serializer.zig").ResolveReq;
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

pub fn Init(self: *WorldManager, width: usize, height: usize, engine_allocator: std.mem.Allocator) !void {
    _ = .{ self, width, height, engine_allocator };
    @panic("WorldManager.Init not implemented");
}

pub fn Deinit(self: *WorldManager, engine_context: *EngineContext) !void {
    _ = .{ self, engine_context };
    @panic("WorldManager.Deinit not implemented");
}

pub fn clearAndFree(self: *WorldManager, engine_context: *EngineContext) !void {
    _ = .{ self, engine_context };
    @panic("WorldManager.clearAndFree not implemented");
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
pub fn AddUUID(self: *WorldManager, engine_allocator: std.mem.Allocator, uuid: u64, world_id: usize) !void {
    _ = .{ self, engine_allocator, uuid, world_id };
    @panic("WorldManager.AddUUID not implemented");
}

pub fn RemoveUUID(self: *WorldManager, uuid: u64) void {
    _ = .{ self, uuid };
    @panic("WorldManager.RemoveUUID not implemented");
}

pub fn GetWorldID(self: WorldManager, uuid: u64) ?usize {
    _ = .{ self, uuid };
    @panic("WorldManager.GetWorldID not implemented");
}

pub fn AddResolveUUID(self: *WorldManager, engine_allocator: std.mem.Allocator, resolve_req: ResolveReq) !void {
    _ = .{ self, engine_allocator, resolve_req };
    @panic("WorldManager.AddResolveUUID not implemented");
}

const WorldManager = @This();

const std = @import("std");

const EngineContext = @import("EngineContext.zig");
const Tracy = @import("Tracy.zig");
const GroupQuery = @import("../ECS/ECSManager.zig").GroupQuery;
const LayerType = @import("../ECSComponents/Scene/SceneComponent.zig").LayerType;
const OverlayCanvas = @import("../Math/OverlayCanvas.zig");
const ESceneComponents = @import("../ECSComponents/SComponents.zig").EComponents;

const Entity = @import("../ECSObjects/Entity.zig");
const GameContext = @import("../ECSObjects/GameContext.zig");
const Player = @import("../ECSObjects/Player.zig");
const Scene = @import("../ECSObjects/Scene.zig");
const AssetHandle = @import("../ECSObjects/AssetHandle.zig");

const EManager = @import("../ECSManagers/EManager.zig");
const GCManager = @import("../ECSManagers/GCManager.zig");
const PManager = @import("../ECSManagers/PManager.zig");
const SManager = @import("../ECSManagers/SManager.zig");
const PhysicsManager = @import("../Physics/PhysicsManager.zig");

const EEventData = @import("../Events/EManagerData.zig");
const GCEventData = @import("../Events/GCManagerData.zig");
const PEventData = @import("../Events/PManagerData.zig");
const SEventData = @import("../Events/SManagerData.zig");
const ECSEventData = @import("../Events/ECSEventData.zig");
const PhysicsEventData = @import("../Events/PhysicsEventData.zig");

const ClearAndFreeOptions = enum {
    All,
    EManager,
    GCManager,
    PManager,
    SManager,
};

mEManager: EManager = .empty,
mGCManager: GCManager = .empty,
mPManager: PManager = .empty,
mSManager: SManager = .empty,

/// What physics carries from one step of this world to the next: leftover step time and which pairs
/// were touching. It is about this world's entities, so it lives and is cleared with them
mPhysicsManager: PhysicsManager = .{},

/// How every overlay scene in this world turns its units into screen pixels: one for all of them, so they all share
/// the one screen space, and the renderer can hold all their shapes in one tree. Each view still places that space
/// on its own camera and resolution. Not saved yet: the editor sets its own world's, game worlds keep the default
mOverlayScaleMode: OverlayCanvas.OverlayScaleMode = .ScaleWithScreen,

/// How many screen pixels one unit of this world's screen space covers, on a target this tall
pub fn OverlayPixelsPerUnit(self: *const WorldManager, target_height: f32, display_scale: f32) f32 {
    return OverlayCanvas.PixelsPerUnit(self.mOverlayScaleMode, target_height, display_scale);
}

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
    try self.mEManager.Init(engine_allocator);
    try self.mGCManager.Init(engine_allocator);
    try self.mPManager.Init(engine_allocator);
    try self.mSManager.Init(engine_allocator);
    try self.mPhysicsManager.Init(engine_allocator);
}

/// Steps this world's physics by the frame's time
pub fn OnPhysicsUpdate(self: *WorldManager, engine_context: *EngineContext) !void {
    try self.mPhysicsManager.OnUpdate(engine_context, self);
}

/// Points every event manager under this world at the engine-wide synchronous listener.
pub fn SetSyncCallback(self: *WorldManager, ctx: anytype, comptime handler: anytype) void {
    self.mEManager.SetSyncCallback(ctx, handler);
    self.mGCManager.SetSyncCallback(ctx, handler);
    self.mPManager.SetSyncCallback(ctx, handler);
    self.mSManager.SetSyncCallback(ctx, handler);
    self.mPhysicsManager.SetSyncCallback(ctx, handler);
}

pub fn Deinit(self: *WorldManager, engine_context: *EngineContext) void {
    self.mEManager.Deinit(engine_context);
    self.mGCManager.Deinit(engine_context);
    self.mPManager.Deinit(engine_context);
    self.mSManager.Deinit(engine_context);
    self.mPhysicsManager.Deinit(engine_context.EngineAllocator());
}

pub fn clearAndFree(self: *WorldManager, engine_context: *EngineContext, options: ClearAndFreeOptions) void {
    const zone = Tracy.ZoneInit("WorldManager::clearAndFree", @src());
    defer zone.Deinit();

    //the physics state names entities by id, so it goes whenever they do
    if (options == .All or options == .EManager) self.mPhysicsManager.Reset(engine_context.EngineAllocator());

    switch (options) {
        .All => {
            self.mEManager.clearAndFree(engine_context);
            self.mGCManager.clearAndFree(engine_context);
            self.mPManager.clearAndFree(engine_context);
            self.mSManager.clearAndFree(engine_context);
        },
        .EManager => self.mEManager.clearAndFree(engine_context),
        .GCManager => self.mGCManager.clearAndFree(engine_context),
        .PManager => self.mPManager.clearAndFree(engine_context),
        .SManager => self.mSManager.clearAndFree(engine_context),
    }
}

pub fn Copy(self: *WorldManager, engine_context: *EngineContext, other_world: *WorldManager) !void {
    const zone = Tracy.ZoneInit("WorldManager::Copy", @src());
    defer zone.Deinit();
    try self.mEManager.Copy(engine_context, &other_world.mEManager);
    try self.mGCManager.Copy(engine_context, &other_world.mGCManager);
    try self.mPManager.Copy(engine_context, &other_world.mPManager);
    try self.mSManager.Copy(engine_context, &other_world.mSManager);

    //the ECS copies components by value, so every object handle in them still points at this world.
    //ids carry over, so only the manager has to change, and only once all four managers are across
    other_world.RetargetHandles();

    //every copied UIElementComponent was copied with an element of its own, which has to be told whose it is
    try engine_context.mUIManager.AdoptWorld(engine_context, other_world);

    //its overlays measure the screen the same way
    other_world.mOverlayScaleMode = self.mOverlayScaleMode;

    //physics state is not copied: the copy starts its own stepping, so nothing in it has touched yet
    other_world.mPhysicsManager.Reset(engine_context.EngineAllocator());
}

/// Points every object handle (Entity, GameContext, Player, Scene) held in this world's components at
/// this world. The same fields ECSObject's Core.AddComponent sets on a new component, for copies that
/// never go through it.
fn RetargetHandles(self: *WorldManager) void {
    self.RetargetECSHandles(&self.mEManager.mECSManager);
    self.RetargetECSHandles(&self.mGCManager.mECSManager);
    self.RetargetECSHandles(&self.mPManager.mECSManager);
    self.RetargetECSHandles(&self.mSManager.mECSManager);
}

fn RetargetECSHandles(self: *WorldManager, ecs_manager: anytype) void {
    inline for (@TypeOf(ecs_manager.*).ComponentTypes) |component_type| {
        //most components hold no handles, and those are skipped at compile time
        if (comptime HoldsObjectHandle(component_type)) {
            const type_info = @typeInfo(component_type);
            for (ecs_manager.GetComponentSlice(component_type)) |*component| {
                inline for (type_info.@"struct".field_types, type_info.@"struct".field_names) |field_type, field_name| {
                    if (comptime IsObjectHandle(field_type)) {
                        @field(component, field_name).mManager = self;
                    }
                }
            }
        }
    }
}

fn HoldsObjectHandle(comptime component_type: type) bool {
    const type_info = @typeInfo(component_type);
    if (type_info != .@"struct") return false;
    for (type_info.@"struct".field_types) |field_type| {
        if (IsObjectHandle(field_type)) return true;
    }
    return false;
}

/// The objects whose mManager is a *WorldManager. An AssetHandle points at the engine's one asset
/// manager, which every world shares, so it is right in a copy as it is.
fn IsObjectHandle(comptime field_type: type) bool {
    return field_type == Entity or
        field_type == GameContext or
        field_type == Player or
        field_type == Scene;
}

pub fn ProcessEvents(self: *WorldManager, comptime event_data: type, comptime event_category: event_data.EventCategories, engine_context: *EngineContext, callback_list: *std.DoublyLinkedList) !void {
    if (event_data == EEventData) {
        try self.mEManager.ProcessEvents(event_data, event_category, engine_context, callback_list);
    } else if (event_data == GCEventData) {
        try self.mGCManager.ProcessEvents(event_data, event_category, engine_context, callback_list);
    } else if (event_data == PEventData) {
        try self.mPManager.ProcessEvents(event_data, event_category, engine_context, callback_list);
    } else if (event_data == SEventData) {
        try self.mSManager.ProcessEvents(event_data, event_category, engine_context, callback_list);
    } else if (event_data == PhysicsEventData) {
        try self.mPhysicsManager.ProcessEvents(event_category, engine_context, callback_list);
    } else if (event_data == ECSEventData) {
        try self.mEManager.ProcessEvents(event_data, event_category, engine_context, callback_list);
        try self.mGCManager.ProcessEvents(event_data, event_category, engine_context, callback_list);
        try self.mPManager.ProcessEvents(event_data, event_category, engine_context, callback_list);
        try self.mSManager.ProcessEvents(event_data, event_category, engine_context, callback_list);
    } else {
        std.log.err("WorldManager.ProcessEvents does not currently handle processing events of type {s}", .{@typeName(event_data)});
    }
}

/// A new scene, player or game context with no components, for one whose components all come from somewhere else
/// (a file, a template). A scene is left out of the stack until a SceneComponent is added through PostParse.
/// Entities are made blank by the scene they go in (Scene.CreateEntity with Entity.BlankConfig)
pub fn CreateBlank(self: *WorldManager, comptime obj_t: type, engine_context: *EngineContext) !obj_t {
    if (obj_t == Scene) {
        return try self.mSManager.CreateBlankScene(engine_context);
    } else if (obj_t == Player) {
        return try self.CreatePlayer(engine_context, Player.BlankConfig);
    } else if (obj_t == GameContext) {
        return try self.CreateGameContext(engine_context, GameContext.BlankConfig);
    } else if (obj_t == Entity) {
        @compileError("an entity has to belong to a scene, create it with Scene.CreateEntity(Entity.BlankConfig)");
    } else {
        @compileError(std.fmt.comptimePrint("{s} is not an object type owned by the WorldManager", .{@typeName(obj_t)}));
    }
}

/// A new copy of the template `tmpl` (a handle to a SceneAsset, PlayerAsset or GCAsset, going by obj_t). It has no
/// UUID and takes the template's name. See Core.Fill. Entities are spawned by the scene they go in (Scene.Spawn)
pub fn Spawn(self: *WorldManager, comptime obj_t: type, engine_context: *EngineContext, tmpl: AssetHandle) !obj_t {
    if (obj_t == Entity) @compileError("an entity has to belong to a scene, spawn it with Scene.Spawn");
    const object = try self.CreateBlank(obj_t, engine_context);
    errdefer object.Delete(engine_context) catch {};
    try object.SetTmpl(engine_context, tmpl);
    return object;
}

//===============================Scenes==============================================
pub fn NewScene(self: *WorldManager, engine_context: *EngineContext, layer_type: LayerType, config: Scene.CreateConfig) !Scene {
    return try self.mSManager.CreateScene(engine_context, layer_type, config);
}

pub fn DestroyScene(self: *WorldManager, engine_context: *EngineContext, destroy_scene: Scene) !void {
    try self.mSManager.DeleteScene(engine_context, destroy_scene.mID);
}

pub fn LoadScene(self: *WorldManager, engine_context: *EngineContext, abs_path: []const u8) !Scene {
    const zone = Tracy.ZoneInit("WorldManager::LoadScene", @src());
    defer zone.Deinit();
    zone.Text(abs_path);
    return try self.mSManager.LoadScene(engine_context, abs_path);
}

pub fn SaveScene(self: *WorldManager, engine_context: *EngineContext, scene: Scene) !void {
    const zone = Tracy.ZoneInit("WorldManager::SaveScene", @src());
    defer zone.Deinit();
    try self.mSManager.SaveScene(engine_context, scene);
}

pub fn SaveSceneAs(self: *WorldManager, engine_context: *EngineContext, scene: Scene) !void {
    try self.mSManager.SaveSceneAs(engine_context, scene);
}

pub fn MoveScene(self: *WorldManager, frame_allocator: std.mem.Allocator, scene: Scene, move_to_pos: usize) !void {
    try self.mSManager.MoveScene(frame_allocator, scene, move_to_pos);
}

pub fn GetSceneGroup(self: *WorldManager, frame_allocator: std.mem.Allocator, comptime query: GroupQuery) !std.ArrayList(Scene.Type) {
    return try self.mSManager.GetGroup(frame_allocator, query);
}

pub fn GetSceneStackIDs(self: *WorldManager, frame_allocator: std.mem.Allocator) !std.ArrayList(Scene.Type) {
    return try self.mSManager.GetSceneStackIDs(frame_allocator);
}

pub fn RmSceneComp(self: *WorldManager, engine_allocator: std.mem.Allocator, scene_id: Scene.Type, component_ind: ESceneComponents) !void {
    _ = .{ self, engine_allocator, scene_id, component_ind };
    @panic("not implemented yet");
}

//===============================Entities==============================================
pub fn GetEntityGroup(self: *WorldManager, frame_allocator: std.mem.Allocator, comptime query: GroupQuery) !std.ArrayList(Entity.Type) {
    return try self.mEManager.GetGroup(frame_allocator, query);
}

/// How many entities in this world have `component_type`, without building a group.
pub fn NumEntitiesWith(self: *WorldManager, comptime component_type: type) usize {
    return self.mEManager.mECSManager.NumWithComponent(component_type);
}

pub fn SaveEntity(self: *WorldManager, engine_context: *EngineContext, entity: Entity) !void {
    const zone = Tracy.ZoneInit("WorldManager::SaveEntity", @src());
    defer zone.Deinit();
    try self.mEManager.SaveEntity(engine_context, entity);
}

pub fn SaveEntityAs(self: *WorldManager, engine_context: *EngineContext, entity: Entity) !void {
    try self.mEManager.SaveEntityAs(engine_context, entity);
}

//===============================Players==============================================
pub fn CreatePlayer(self: *WorldManager, engine_context: *EngineContext, config: Player.CreateConfig) !Player {
    return try self.mPManager.CreatePlayer(engine_context, config);
}

pub fn GetPlayerGroup(self: *WorldManager, frame_allocator: std.mem.Allocator, comptime query: GroupQuery) !std.ArrayList(Player.Type) {
    return try self.mPManager.GetGroup(frame_allocator, query);
}

//===============================Game Contexts (formerly GameModes)==============================================
pub fn CreateGameContext(self: *WorldManager, engine_context: *EngineContext, config: GameContext.CreateConfig) !GameContext {
    return try self.mGCManager.CreateGameContext(engine_context, config);
}

pub fn GetGameContextGroup(self: *WorldManager, frame_allocator: std.mem.Allocator, comptime query: GroupQuery) !std.ArrayList(GameContext.Type) {
    return try self.mGCManager.GetGroup(frame_allocator, query);
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

const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const TransformSystem = @import("TransformSystem.zig");
const PhysicsStepSystem = @import("PhysicsStepSystem.zig");
const WorldManager = @import("../Core/WorldManager.zig");
const CollisionManager = @import("CollisionManager.zig");

const EventData = @import("../Events/PhysicsEventData.zig");
pub const EventManagerT = @import("../Events/EventManager.zig").EventManager(EventData);

const Tracy = @import("../Core/Tracy.zig");

const PhysicsManager = @This();

const InternalData = struct {
    pub const empty: InternalData = .{
        .Accumulator = 0,
    };

    Accumulator: f32,
};

const PHYSICS_DT: f32 = 1.0 / 60.0;

/// How many substeps one fixed step is split into (PhysicsStepSystem)
pub const SUB_STEPS: u32 = 2;
pub const SUB_STEP_DT: f32 = PHYSICS_DT / @as(f32, @floatFromInt(SUB_STEPS));

/// What the steps have to report, e.g. the collisions that began. Nothing in here listens to it:
/// whoever steps the world processes it afterwards, see ProcessEvents
mEventManager: EventManagerT = .empty,

/// While true the world's physics stands still, see SetPaused
mPaused: bool = false,

_CollisionManager: CollisionManager = .empty,
_InternalData: InternalData = .empty,

pub fn Init(self: *PhysicsManager, engine_allocator: std.mem.Allocator) !void {
    try self._CollisionManager.Init(engine_allocator);
}

pub fn Deinit(self: *PhysicsManager, engine_allocator: std.mem.Allocator) void {
    const zone = Tracy.ZoneInit("PhysicsManager::Deinit", @src());
    defer zone.Deinit();
    self._CollisionManager.Deinit(engine_allocator);
    self.mEventManager.Deinit(engine_allocator);
}

/// Points this manager's events at the engine-wide synchronous listener
pub fn SetSyncCallback(self: *PhysicsManager, ctx: anytype, comptime handler: anytype) void {
    self.mEventManager.SetSyncCallback(ctx, handler);
}

/// Hands the events queued in a category to the caller's listeners, then empties it
pub fn ProcessEvents(self: *PhysicsManager, comptime event_category: EventData.EventCategories, engine_context: *EngineContext, callback_list: *std.DoublyLinkedList) !void {
    try self.mEventManager.ProcessCategory(event_category, engine_context, callback_list.*);
    self.mEventManager.ClearCategory(engine_context.EngineAllocator(), event_category, .ClearRetainingCapacity);
}

/// Pauses or carries on the world's physics, e.g. from a pause menu's script. While paused there are no physics steps:
/// nothing moves by its velocity, no forces or gravity, no collisions or their scripts, and no OnPhysicsUpdate scripts.
/// Time doesn't build up meanwhile, so carrying on doesn't run the paused time's steps all at once. Only the physics
/// stops: OnUpdate scripts still run, and one that moves things itself checks IsPaused
pub fn SetPaused(self: *PhysicsManager, paused: bool) void {
    self.mPaused = paused;
}

pub fn IsPaused(self: PhysicsManager) bool {
    return self.mPaused;
}

/// Drops everything carried from one step to the next: the leftover time, which pairs were touching,
/// and any events not processed yet. For when the owning world's entities are cleared out or replaced,
/// since their ids then mean different objects. Unpauses too: pressing play copies a world through this, and a game
/// quit while paused starts running the next time
pub fn Reset(self: *PhysicsManager, engine_allocator: std.mem.Allocator) void {
    self.mPaused = false;
    self._InternalData = .empty;
    self._CollisionManager.Reset(engine_allocator);
    self.mEventManager.EventsReset(engine_allocator, .ClearRetainingCapacity);
}

/// world_manager is the world that owns this PhysicsManager, see WorldManager.OnPhysicsUpdate
pub fn OnUpdate(self: *PhysicsManager, engine_context: *EngineContext, world_manager: *WorldManager) !void {
    const zone = Tracy.ZoneInit("PhysicsManager::OnUpdate", @src());
    defer zone.Deinit();

    //before the time is added, so a paused world builds none up to catch up on later
    if (self.mPaused) return;

    self._InternalData.Accumulator += engine_context.mDT;

    //fixed steps run this frame: normally 0 or 1, and climbing means physics is falling behind real time
    var steps: usize = 0;
    defer Tracy.Plot("Physics/Steps Per Frame", .{ .color = 0xF44336 }, steps);

    //the same condition the step loop below runs on, so a frame that will not step skips the group
    //queries too instead of building lists nothing reads
    if (self._InternalData.Accumulator < PHYSICS_DT) return;

    while (self._InternalData.Accumulator >= PHYSICS_DT) : (self._InternalData.Accumulator -= PHYSICS_DT) {
        steps += 1;
        try self.Step(engine_context, world_manager);
    }
}

/// One fixed step of PHYSICS_DT. Whatever acts at the physics' own rate does so first (StepBeginEvent, which
/// runs OnPhysicsUpdate scripts), then the substeps, then the forces applied for the step are let go of.
fn Step(self: *PhysicsManager, engine_context: *EngineContext, world_manager: *WorldManager) !void {
    //synchronous, so everything listening is done before the step goes on
    _ = try self.mEventManager.Dispatch(engine_context, .{ .StepBegin = .{ .mWorld = world_manager, .mDT = PHYSICS_DT } });
    //what the listeners moved or turned, so the step starts from it. A local constant force reads the rotation
    try engine_context.mSystems.RunSystem(TransformSystem, engine_context, .{world_manager});

    try engine_context.mSystems.RunSystem(PhysicsStepSystem, engine_context, .{world_manager});
}

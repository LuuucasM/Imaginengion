const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const WorldManager = @import("../Core/WorldManager.zig");

const Entity = @import("../ECSObjects/Entity.zig");

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const RigidBodyComponent = EntityComponents.RigidBodyComponent;
const DynamicBodyTag = EntityComponents.DynamicBodyTag;
const KinematicBodyTag = EntityComponents.KinematicBodyTag;
const ConstantForceComponent = EntityComponents.ConstantForceComponent;
const GroupQuery = @import("../ECS/ECSManager.zig").GroupQuery;
const ColliderComponent = EntityComponents.ColliderComponent;
const EntitySceneComponent = EntityComponents.EntitySceneComponent;
const EntityTransformComponent = EntityComponents.TransformComponent;
const ChildComponent = @import("../ECS/Components.zig").ChildComponent(Entity.Type);
const ParentComponent = @import("../ECS/Components.zig").ParentComponent(Entity.Type);
const TransformDirtyTag = EntityComponents.TransformDirtyTag;
const SceneComponents = @import("../ECSComponents/SComponents.zig");
const ScenePhysicsComponent = SceneComponents.PhysicsComponent;
const CollisionManager = @import("CollisionManager.zig");

const EventData = @import("../Events/PhysicsEventData.zig");
pub const EventManagerT = @import("../Events/EventManager.zig").EventManager(EventData);

const MathTypes = @import("../Math/MathTypes.zig");
const Vec3 = MathTypes.Vec3;
const Quat = MathTypes.Quat;

const Collisions = @import("Collisions.zig");
const Contact = Collisions.Contact;

const Tracy = @import("../Core/Tracy.zig");

const PhysicsManager = @This();

const InternalData = struct {
    pub const empty: InternalData = .{
        .Accumulator = 0,
    };

    Accumulator: f32,
};

const PHYSICS_DT: f32 = 1.0 / 60.0;

const RigidBodyQuery = GroupQuery{ .Component = RigidBodyComponent };
//moved by forces, gravity and their velocity
const DynamicBodiesQuery = GroupQuery{ .And = &.{ RigidBodyQuery, GroupQuery{ .Component = DynamicBodyTag } } };
//moved by their velocity alone. static bodies have no query: they are never integrated
const KinematicBodiesQuery = GroupQuery{ .And = &.{ RigidBodyQuery, GroupQuery{ .Component = KinematicBodyTag } } };
//the dynamic bodies with a push that stays on them, the only ones a constant force can move
const ConstantForceBodiesQuery = GroupQuery{ .And = &.{ DynamicBodiesQuery, GroupQuery{ .Component = ConstantForceComponent } } };

const SUB_STEPS: u32 = 2;

//the transform walk adds translations and multiplies rotations and scales,
//so this is what a root of the hierarchy accumulates from
const IDENTITY_POSITION: Vec3(f32) = .{ .x = 0.0, .y = 0.0, .z = 0.0 };
const IDENTITY_ROTATION: Quat(f32) = .{ .w = 1.0, .x = 0.0, .y = 0.0, .z = 0.0 };
const IDENTITY_SCALE: Vec3(f32) = .{ .x = 1.0, .y = 1.0, .z = 1.0 };
const SUB_STEP_DT: f32 = PHYSICS_DT / @as(f32, @floatFromInt(SUB_STEPS));

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
    try UpdateWorldTransforms(world_manager, engine_context);

    //fetched after the listeners, which may have added bodies or changed their types, and once for every substep
    //below: nothing inside the substeps adds or removes a collider or a body tag, so the lists can't go stale
    const frame_allocator = engine_context.FrameAllocator();
    const dynamic_bodies = try world_manager.GetEntityGroup(frame_allocator, DynamicBodiesQuery);
    const kinematic_bodies = try world_manager.GetEntityGroup(frame_allocator, KinematicBodiesQuery);
    const moving_body_count = dynamic_bodies.items.len + kinematic_bodies.items.len;
    Tracy.Plot("Physics/Moving Bodies", .{ .color = 0xE91E63 }, moving_body_count);

    const collider_groups = try CollisionManager.QueryColliderGroups(world_manager, frame_allocator);

    //added in with whatever the listeners applied, after them so a script that changes a constant force has it
    //count from this step. Part of the step's forces from here on, felt on every substep and let go of at the end
    const constant_force_bodies = try world_manager.GetEntityGroup(frame_allocator, ConstantForceBodiesQuery);
    for (constant_force_bodies.items) |entity_id| {
        const entity = world_manager.GetEntity(entity_id);
        const constant_force = entity.GetComponent(ConstantForceComponent).?;
        //the local one turned the way the body faces, into world space with the other
        const rotation = entity.GetComponent(EntityTransformComponent).?.GetWorldRotation();
        const force = constant_force.mForce.AddVec(constant_force.mLocalForce.QuatRotate(rotation));
        entity.GetComponent(RigidBodyComponent).?.ApplyForce(force);
    }

    //contacts are found before anything moves, from where the bodies are and how fast they are going, so
    //the solver can stop a body at a surface before the move that would have carried it through
    for (0..SUB_STEPS) |_| {
        {
            //one zone for the whole pass: per-body zones would cost more than the few multiply-adds they time
            const integrate_zone = Tracy.ZoneInit("PhysicsManager::IntegrateVelocities", @src());
            defer integrate_zone.Deinit();
            integrate_zone.Value(dynamic_bodies.items.len);

            //only dynamic bodies: code sets a kinematic body's velocity and nothing else changes it, no
            //gravity and no force
            for (dynamic_bodies.items) |entity_id| {
                const entity = world_manager.GetEntity(entity_id);
                const entity_rb = entity.GetComponent(RigidBodyComponent).?;
                IntegrateVelocities(entity_rb, GravityOf(entity, entity_rb), SUB_STEP_DT);
            }
        }

        //where the bodies start the substep, which is what the contacts are measured from
        try UpdateWorldTransforms(world_manager, engine_context);

        try self._CollisionManager.BroadPass(engine_context, world_manager, collider_groups);
        self._CollisionManager.NarrowPass(SUB_STEP_DT);
        try self._CollisionManager.PreSolverPass(engine_context, &self.mEventManager);
        self._CollisionManager.SolveVelocities(SUB_STEP_DT);
        self._CollisionManager.SweepTriggers(SUB_STEP_DT);

        {
            const integrate_zone = Tracy.ZoneInit("PhysicsManager::IntegratePositions", @src());
            defer integrate_zone.Deinit();
            integrate_zone.Value(moving_body_count);

            for (dynamic_bodies.items) |entity_id| {
                const entity = world_manager.GetEntity(entity_id);
                try IntegratePositions(engine_context, entity, entity.GetComponent(RigidBodyComponent).?, SUB_STEP_DT);
            }
            for (kinematic_bodies.items) |entity_id| {
                const entity = world_manager.GetEntity(entity_id);
                try IntegratePositions(engine_context, entity, entity.GetComponent(RigidBodyComponent).?, SUB_STEP_DT);
            }
        }

        try self._CollisionManager.CorrectPositions(world_manager, engine_context);
        try self._CollisionManager.UpdateTouching(engine_context, &self.mEventManager);
        try self._CollisionManager.PostsolverPass(engine_context);
        self._CollisionManager.EndPass(engine_context);
    }

    //a force pushes for one step. Whatever applied it applies it again next step for as long as it should keep
    //pushing. A kinematic body's are let go of too: it is never pushed by them, but they shouldn't pile up
    for (dynamic_bodies.items) |entity_id| {
        world_manager.GetEntity(entity_id).GetComponent(RigidBodyComponent).?._Force = std.mem.zeroes(Vec3(f32));
    }
    for (kinematic_bodies.items) |entity_id| {
        world_manager.GetEntity(entity_id).GetComponent(RigidBodyComponent).?._Force = std.mem.zeroes(Vec3(f32));
    }
}

pub fn UpdateWorldTransforms(world_manager: *WorldManager, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("PhysicsManager::UpdateWorldTransforms", @src());
    defer zone.Deinit();

    //only entities whose local transform changed since the last pass, which is a single component
    //query and so costs O(dirty) rather than the whole world. Every write goes through Entity's
    //transform setters, which is what puts the tag on.
    const dirty_arr = try world_manager.GetEntityGroup(
        engine_context.FrameAllocator(),
        .{ .Component = TransformDirtyTag },
    );

    for (dirty_arr.items) |entity_id| {
        const entity = world_manager.GetEntity(entity_id);

        //a dirty entity is not necessarily a root, so the walk starts from whatever its nearest
        //ancestor-with-a-transform already worked out. That ancestor is either clean, or dirty too
        //and its own pass rewrites this subtree; both orders land on the same answer because
        //CalculateEntityTransform assigns world from local and the accumulator instead of accumulating
        //into itself. That is also why a parent and child both being dirty is merely redundant work
        //rather than wrong, so nothing here tries to skip entities that have a dirty ancestor.
        const seed = AncestorWorldTransform(entity);
        CalculateEntityTransform(entity, seed.position, seed.rotation, seed.scale);

        //cleared synchronously, so this entity is clean the moment its subtree is done. The later
        //passes in the same frame (a physics substep, a solver iteration) then see only what has
        //moved since, and a move that happens after this point re-tags rather than being swallowed
        //by a tag that is still sitting there waiting for end of frame.
        //Safe to remove mid-iteration: dirty_arr is a copy of the dense array, not a view of it.
        try entity.ClearTransformDirty(engine_context);
    }
}

const SeedTransform = struct {
    position: Vec3(f32),
    rotation: Quat(f32),
    scale: Vec3(f32),
};

/// The accumulator a dirty entity's subtree walk starts from: the cached world transform of the
/// nearest ancestor that has a TransformComponent. Convenience entities without one contribute
/// nothing but do not stop the walk, matching Entity._CalculateWorldTransform. An entity that
/// roots the hierarchy gets the identities.
fn AncestorWorldTransform(entity: Entity) SeedTransform {
    var child_component = entity.GetComponent(ChildComponent);

    while (child_component) |child| {
        const parent_entity = Entity{ .mID = child.mParent, .mManager = entity.mManager };

        if (parent_entity.GetComponent(EntityTransformComponent)) |parent_transform| {
            return .{
                .position = parent_transform.GetWorldPosition(),
                .rotation = parent_transform.GetWorldRotation(),
                .scale = parent_transform.GetWorldScale(),
            };
        }

        child_component = parent_entity.GetComponent(ChildComponent);
    }

    return .{ .position = IDENTITY_POSITION, .rotation = IDENTITY_ROTATION, .scale = IDENTITY_SCALE };
}

fn CalculateChildren(parent_entity: Entity, position_acc: Vec3(f32), rotation_acc: Quat(f32), scale_acc: Vec3(f32)) void {
    const parent_component = parent_entity.GetComponent(ParentComponent).?;

    //an entity with only script children still has a ParentComponent, its entity list is just empty
    if (parent_component.mFirstEntity == Entity.NullObject) return;

    var curr_id = parent_component.mFirstEntity;

    while (true) : (if (curr_id == parent_component.mFirstEntity) break) {
        const child_entity = Entity{ .mID = curr_id, .mManager = parent_entity.mManager };

        CalculateEntityTransform(child_entity, position_acc, rotation_acc, scale_acc);

        const child_component = child_entity.GetComponent(ChildComponent).?;
        curr_id = child_component.mNext;
    }
}

fn CalculateEntityTransform(entity: Entity, position_acc: Vec3(f32), rotation_acc: Quat(f32), scale_acc: Vec3(f32)) void {
    //a convenience entity is just a bundle of components hanging off its parent, so it can be
    //missing a TransformComponent. It contributes nothing then, but the walk still goes through
    //it: its own children keep accumulating from the nearest ancestor that does have one.
    var position_out = position_acc;
    var rotation_out = rotation_acc;
    var scale_out = scale_acc;

    if (entity.GetComponent(EntityTransformComponent)) |transform| {
        //the local position is an offset in the parent's space: it stretches with the parent's scale
        //and turns with its rotation before it is added on, so a child orbits a turning parent and
        //moves out with a growing one instead of staying put
        transform.SetWorldPosition(position_acc.AddVec(transform.GetTranslation().MulVec(scale_acc).QuatRotate(rotation_acc)));
        transform.SetWorldRotation(rotation_acc.MulQuat(transform.GetRotation()));
        //scale composes multiplicatively: a child is a factor of its parent, not an offset from it.
        //Entity._CalculateWorldTransform has to keep using the same three rules, or a deserialized
        //hierarchy disagrees with a live-edited one.
        transform.SetWorldScale(transform.GetScale().MulVec(scale_acc));

        position_out = transform.GetWorldPosition();
        rotation_out = transform.GetWorldRotation();
        scale_out = transform.GetWorldScale();
    }

    if (entity.HasComponent(ParentComponent)) {
        CalculateChildren(entity, position_out, rotation_out, scale_out);
    }
}

/// How fast gravity speeds a dynamic body up: its scene's gravity, scaled axis by axis by the body's gravity scale.
/// Nothing in a scene with no physics settings
fn GravityOf(entity: Entity, entity_rb: *const RigidBodyComponent) Vec3(f32) {
    const scene_layer = entity.GetComponent(EntitySceneComponent).?.mScene;
    const physics_component = scene_layer.GetComponent(ScenePhysicsComponent) orelse return std.mem.zeroes(Vec3(f32));
    //the scene sets which way gravity pulls and how hard, the body how much of each axis it feels
    return physics_component.mGravity.MulVec(entity_rb.mGravityScale);
}

/// Speeds a dynamic body up by gravity and by the forces applied to it this step. The forces stay in _Force until
/// the step is over, so every substep of the step feels them
fn IntegrateVelocities(entity_rb: *RigidBodyComponent, gravity: Vec3(f32), dt: f32) void {
    const acceleration = gravity.AddVec(entity_rb._Force.MulScalar(entity_rb._InvMass));
    entity_rb.AddVelocity(acceleration.MulScalar(dt));
}

fn IntegratePositions(engine_context: *EngineContext, entity: Entity, entity_rb: *RigidBodyComponent, dt: f32) !void {
    const transform = entity.GetComponent(EntityTransformComponent).?;
    var translation = transform.GetTranslation();
    translation.AddEqVec(entity_rb._Velocity.MulScalar(dt));
    try entity.SetTranslation(engine_context, translation);
}

const std = @import("std");
const Collisions = @import("Collisions.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const Tracy = @import("../Core/Tracy.zig");
const Contact = Collisions.Contact;
const EntityComponents = @import("../ECSComponents/EComponents.zig");
const ColliderComponent = EntityComponents.ColliderComponent;
const EntityTransformComponent = EntityComponents.TransformComponent;
const RigidBodyComponent = EntityComponents.RigidBodyComponent;
const DynamicBodyTag = EntityComponents.DynamicBodyTag;
const KinematicBodyTag = EntityComponents.KinematicBodyTag;
const StaticBodyTag = EntityComponents.StaticBodyTag;
const GroupQuery = @import("../ECS/ECSManager.zig").GroupQuery;
const Entity = @import("../ECSObjects/Entity.zig");
const WorldManager = @import("../Core/WorldManager.zig");
const SkipField = @import("../Core/SkipField.zig").StaticSkipField;
const UpdateWorldTransforms = @import("PhysicsManager.zig").UpdateWorldTransforms;
const PhysicsEventManager = @import("PhysicsManager.zig").EventManagerT;
const CollisionType = @import("Collisions.zig").CollisionType;
const MathTypes = @import("../Math/MathTypes.zig");
const Vec3 = MathTypes.Vec3;
const ImguiManager = @import("../Imgui/Imgui.zig");

const ColliderQuery = GroupQuery{ .Component = ColliderComponent };
const DynamicQuery = GroupQuery{ .Component = DynamicBodyTag };
const KinematicQuery = GroupQuery{ .Component = KinematicBodyTag };
const MovingQuery = GroupQuery{ .Or = &.{ DynamicQuery, KinematicQuery } };

//colliders the solver can actually move
const DynamicCollidersQuery = GroupQuery{ .And = &.{ ColliderQuery, DynamicQuery } };

//colliders moved by code, which the solver can't move
const KinematicCollidersQuery = GroupQuery{ .And = &.{ ColliderQuery, KinematicQuery } };

//everything that collides and never moves: static bodies, and colliders carrying no RigidBodyComponent at
//all. Asking for "collider and neither dynamic nor kinematic" rather than "collider and static" is deliberate,
//so that a collider with no rigid body (which has no body type tag) still takes part in collision as a static
//body would, instead of silently dropping out of the broad pass.
const StaticCollidersQuery = GroupQuery{ .Not = .{ .mFirst = &ColliderQuery, .mSecond = &MovingQuery } };

/// A world's colliders split by how they move, which decides what the broad pass pairs them with
pub const ColliderGroups = struct {
    mDynamic: []const Entity.Type,
    mKinematic: []const Entity.Type,
    mStatic: []const Entity.Type,
};

pub fn QueryColliderGroups(world_manager: *WorldManager, frame_allocator: std.mem.Allocator) !ColliderGroups {
    return .{
        .mDynamic = (try world_manager.GetEntityGroup(frame_allocator, DynamicCollidersQuery)).items,
        .mKinematic = (try world_manager.GetEntityGroup(frame_allocator, KinematicCollidersQuery)).items,
        .mStatic = (try world_manager.GetEntityGroup(frame_allocator, StaticCollidersQuery)).items,
    };
}

/// Which pairs AddBroadPair keeps: any that can interact, or only those where one side is a trigger
const Pairing = enum {
    Any,
    TriggerOnly,
};

const SOLVER_ITERS: u32 = 4;
const PERCENT: f32 = 0.8;
const SLOP: f32 = 0.01;

//how much further than they could close in a substep two colliders are still treated as a contact. Covers
//what the substep's own motion misses, e.g. a resting body that gravity has not started moving yet
const SPECULATIVE_MARGIN: f32 = 2.0 * SLOP;

//closing speeds below this do not bounce. A body resting on the floor gets a small closing speed from
//gravity every substep, and bouncing that away would keep it hopping instead of settling
const RESTITUTION_THRESHOLD: f32 = 1.0;

const CollisionManager = @This();

/// One pair of colliders whose shapes overlap on a substep
const Touch = struct {
    mKey: u64,
    //where the pair's Contact is: in _OverlapContacts if mIsTrigger, in _BlockingContacts if not.
    //only good for the substep that made it, the contact lists are rebuilt on the next one
    mContactInd: u32,
    mIsTrigger: bool,

    fn LessThan(_: void, a: Touch, b: Touch) bool {
        return a.mKey < b.mKey;
    }
};

/// Both ids in one number, smaller one in the high half. The order the two are given in does not
/// matter, so a pair keeps its key when the broad pass swaps which side it calls the origin
pub fn PairKey(a: Entity.Type, b: Entity.Type) u64 {
    return @as(u64, @min(a, b)) << 32 | @as(u64, @max(a, b));
}

pub const CollisionFilter = struct {
    pub const default: CollisionFilter = .{
        .IsTrigger = false,
        .CategoryMask = .empty,
        .RespondMask = .empty,
    };
    pub fn ImguiRender(self: *CollisionFilter) !void {
        try ImguiManager.RenderBool(&self.IsTrigger, "Is Trigger?");
        try ImguiManager.RenderStaticBitSet(std.StaticBitSet(32), &self.CategoryMask, "Category Mask");
        try ImguiManager.RenderStaticBitSet(std.StaticBitSet(32), &self.RespondMask, "Response Mask");
    }
    IsTrigger: bool,
    CategoryMask: std.StaticBitSet(32),
    RespondMask: std.StaticBitSet(32),
};

pub const empty: CollisionManager = .{
    ._TouchingLast = .empty,
    ._TouchingNow = .empty,
    ._BlockingContacts = .empty,
    ._OverlapContacts = .empty,
};

//the pairs touching on the last substep and on this one, both sorted by key. They outlive the frame,
//which is why they are on the engine allocator and not the frame one
_TouchingLast: std.ArrayList(Touch),
_TouchingNow: std.ArrayList(Touch),
_BlockingContacts: std.ArrayList(Contact),
_OverlapContacts: std.ArrayList(Contact),

pub fn Init(_: *CollisionManager, _: std.mem.Allocator) !void {}

pub fn Deinit(self: *CollisionManager, engine_allocator: std.mem.Allocator) void {
    self._TouchingLast.deinit(engine_allocator);
    self._TouchingNow.deinit(engine_allocator);
    self._BlockingContacts.deinit(engine_allocator);
    self._OverlapContacts.deinit(engine_allocator);
}

/// Forgets which pairs were touching too, so whatever is touching on the next substep counts as new
pub fn Reset(self: *CollisionManager, engine_allocator: std.mem.Allocator) void {
    self._TouchingLast.clearRetainingCapacity();
    self._TouchingNow.clearRetainingCapacity();
    self._BlockingContacts.clearRetainingCapacity();
    self._OverlapContacts.clearRetainingCapacity();
    _ = engine_allocator;
}

///Checks the whole scene for objects that can possibly collide.
/// For the contact sets the entity origin, target, and collision type.
/// groups is QueryColliderGroups, fetched once by the caller for every substep rather than re-queried
/// here each time.
pub fn BroadPass(self: *CollisionManager, engine_context: *EngineContext, world_manager: *WorldManager, groups: ColliderGroups) !void {
    const zone = Tracy.ZoneInit("CollisionManager::BroadPass", @src());
    defer zone.Deinit();

    //a dynamic body can be pushed, so every pair with one in it can need solving: dynamic against everything
    for (0..groups.mDynamic.len) |i| {
        for (i + 1..groups.mDynamic.len) |j| {
            try self.AddBroadPair(engine_context, world_manager, groups.mDynamic[i], groups.mDynamic[j], .Any);
        }
    }
    for (groups.mDynamic) |origin_id| {
        for (groups.mKinematic) |target_id| {
            try self.AddBroadPair(engine_context, world_manager, origin_id, target_id, .Any);
        }
        for (groups.mStatic) |target_id| {
            try self.AddBroadPair(engine_context, world_manager, origin_id, target_id, .Any);
        }
    }

    //a kinematic body against a static or another kinematic one: neither can be pushed, so all such a pair
    //can give is the event of them touching. Built only when one side is a trigger, where the event is the
    //point (a platform entering a zone). Two solid ones would be work every substep for an event that is
    //rarely wanted, an elevator against its shaft. Static against static is never built: neither ever moves.
    for (groups.mKinematic) |origin_id| {
        for (groups.mStatic) |target_id| {
            try self.AddBroadPair(engine_context, world_manager, origin_id, target_id, .TriggerOnly);
        }
    }
    for (0..groups.mKinematic.len) |i| {
        for (i + 1..groups.mKinematic.len) |j| {
            try self.AddBroadPair(engine_context, world_manager, groups.mKinematic[i], groups.mKinematic[j], .TriggerOnly);
        }
    }

    Tracy.Plot("Physics/Broad Pairs", .{ .color = 0x795548 }, self._BlockingContacts.items.len + self._OverlapContacts.items.len);
}

/// Classifies one pair and records it if the two can interact at all.
fn AddBroadPair(self: *CollisionManager, engine_context: *EngineContext, world_manager: *WorldManager, origin_id: Entity.Type, target_id: Entity.Type, comptime pairing: Pairing) !void {
    const entity_origin = world_manager.GetEntity(origin_id);
    const entity_target = world_manager.GetEntity(target_id);

    const collider_origin = entity_origin.GetComponent(ColliderComponent).?;
    const collider_target = entity_target.GetComponent(ColliderComponent).?;

    const collision_type = GetCollisionType(collider_origin, collider_target);

    if (collision_type == .Ignore) return;
    if (pairing == .TriggerOnly and collision_type == .Block) return;

    const contact: Contact = .{
        .mOrigin = entity_origin,
        .mTarget = entity_target,
        .mNormal = Vec3(f32){ .x = 0, .y = 0, .z = 0 },
        .mSeparation = 0,
    };

    switch (collision_type) {
        .Block => try self._BlockingContacts.append(engine_context.EngineAllocator(), contact),
        .Overlap => try self._OverlapContacts.append(engine_context.EngineAllocator(), contact),
        .Ignore => unreachable,
    }
}

///Measures every pair the broad pass found: the gap between them and the direction, for the contact.
/// Runs before anything has moved this substep. A pair is kept while the two overlap or are close enough to
/// meet within dt. For a solid pair that is a speculative contact, so the solver can stop them at the surface
/// before they move rather than find them already through each other. For a trigger pair it is a pair that
/// SweepTriggers checks the path of, since nothing stops a body going through a trigger.
pub fn NarrowPass(self: *CollisionManager, dt: f32) void {
    const zone = Tracy.ZoneInit("CollisionManager::NarrowPass", @src());
    defer zone.Deinit();
    zone.Value(self._OverlapContacts.items.len + self._BlockingContacts.items.len);

    var i: usize = 0;
    var end: usize = self._OverlapContacts.items.len;
    while (i < end) {
        const contact = &self._OverlapContacts.items[i];
        const collider_origin = contact.mOrigin.GetComponent(ColliderComponent).?;
        const collider_target = contact.mTarget.GetComponent(ColliderComponent).?;

        const origin_transform = contact.mOrigin.GetComponent(EntityTransformComponent).?;
        const target_transform = contact.mTarget.GetComponent(EntityTransformComponent).?;

        _ = Collisions.TestShapes(contact, origin_transform, collider_origin, target_transform, collider_target);
        if (contact.mSeparation < SpeculativeReach(contact.*, dt)) {
            i += 1;
        } else {
            self._OverlapContacts.items[i] = self._OverlapContacts.items[end - 1];
            end -= 1;
        }
    }
    self._OverlapContacts.items.len = end;

    i = 0;
    end = self._BlockingContacts.items.len;
    while (i < end) {
        const contact = &self._BlockingContacts.items[i];
        const collider_origin = contact.mOrigin.GetComponent(ColliderComponent).?;
        const collider_target = contact.mTarget.GetComponent(ColliderComponent).?;

        const origin_transform = contact.mOrigin.GetComponent(EntityTransformComponent).?;
        const target_transform = contact.mTarget.GetComponent(EntityTransformComponent).?;

        _ = Collisions.TestShapes(contact, origin_transform, collider_origin, target_transform, collider_target);
        if (contact.mSeparation < SpeculativeReach(contact.*, dt)) {
            i += 1;
        } else {
            self._BlockingContacts.items[i] = self._BlockingContacts.items[end - 1];
            end -= 1;
        }
    }
    self._BlockingContacts.items.len = end;

    //what survived the narrow test, against the broad pair count plotted in BroadPass: a wide gap means
    //the broad phase is handing over many pairs that never touch
    Tracy.Plot("Physics/Blocking Contacts", .{ .color = 0xFF5722 }, self._BlockingContacts.items.len);
    Tracy.Plot("Physics/Overlap Contacts", .{ .color = 0xFFC107 }, self._OverlapContacts.items.len);
}

/// How far apart two colliders can be and still meet within dt: as far as they could close at the speed
/// they are moving relative to each other, plus SPECULATIVE_MARGIN. Their whole relative speed rather than
/// just its part along the normal, so a pair sliding past each other is not missed
fn SpeculativeReach(contact: Contact, dt: f32) f32 {
    const relative_velocity = VelocityOf(contact.mTarget, contact.mTarget.GetComponent(RigidBodyComponent)).SubVec(VelocityOf(contact.mOrigin, contact.mOrigin.GetComponent(RigidBodyComponent)));
    return relative_velocity.Len() * dt + SPECULATIVE_MARGIN;
}

/// Works out which of this substep's contacts are new and queues a CollisionBeginEvent for each. Runs once the
/// solver is done, since a solid pair touches when the solver pushed them apart, whether or not they ever
/// overlapped (a fast ball stopped at a brick's surface), or when they are within SLOP of each other (a body
/// resting on another). A speculative contact the solver never needed is a near miss and does not touch.
/// A trigger pair touches while it overlaps, or when its path went into the trigger this substep (SweepTriggers).
pub fn UpdateTouching(self: *CollisionManager, engine_context: *EngineContext, event_manager: *PhysicsEventManager) !void {
    const engine_allocator = engine_context.EngineAllocator();

    self._TouchingNow.clearRetainingCapacity();
    try self._TouchingNow.ensureTotalCapacity(engine_allocator, self._BlockingContacts.items.len + self._OverlapContacts.items.len);
    for (self._BlockingContacts.items, 0..) |contact, contact_ind| {
        if (contact.mImpulse <= 0.0 and contact.mSeparation > SLOP) continue;
        self._TouchingNow.appendAssumeCapacity(.{ .mKey = PairKey(contact.mOrigin.mID, contact.mTarget.mID), .mContactInd = @intCast(contact_ind), .mIsTrigger = false });
    }
    for (self._OverlapContacts.items, 0..) |contact, contact_ind| {
        if (contact.mSeparation >= 0.0 and !contact.mCrossed) continue;
        self._TouchingNow.appendAssumeCapacity(.{ .mKey = PairKey(contact.mOrigin.mID, contact.mTarget.mID), .mContactInd = @intCast(contact_ind), .mIsTrigger = true });
    }

    //_TouchingLast was sorted the same way a substep ago, so with this one sorted the two can be walked
    //side by side: a key can only be missing from the other list if that list has already moved past it
    std.sort.pdq(Touch, self._TouchingNow.items, {}, Touch.LessThan);

    const last = self._TouchingLast.items;
    var last_ind: usize = 0;
    for (self._TouchingNow.items) |touch| {
        //keys in last below this one were touching and no longer are. an end collision event would go
        //here, and for whatever is left of last once this loop is done
        while (last_ind < last.len and last[last_ind].mKey < touch.mKey) : (last_ind += 1) {}

        if (last_ind < last.len and last[last_ind].mKey == touch.mKey) {
            //still touching, which is what keeps a pair from being reported every substep it is in contact
            last_ind += 1;
            continue;
        }

        const contact = if (touch.mIsTrigger) self._OverlapContacts.items[touch.mContactInd] else self._BlockingContacts.items[touch.mContactInd];
        try event_manager.Insert(engine_allocator, .PostPhysics, .{ .CollisionBegin = .{
            .mOrigin = contact.mOrigin,
            .mTarget = contact.mTarget,
            .mNormal = contact.mNormal,
            .mIsTrigger = touch.mIsTrigger,
        } });
    }

    //swapped rather than copied: this substep's list is the next one's last, and the old last's
    //storage is what the next substep fills
    std.mem.swap(std.ArrayList(Touch), &self._TouchingLast, &self._TouchingNow);
}

pub fn PreSolverPass(self: *CollisionManager, engine_context: *EngineContext) !void {
    _ = engine_context;
    for (self._OverlapContacts.items) |contact| {
        _ = contact;
        //trigger a PreSolverEvent
    }
    for (self._BlockingContacts.items) |contact| {
        _ = contact;
        //trigger a PreSolverEvent
    }
}

/// Sets the velocities the bodies move with this substep, before they move. Three passes over the solid contacts:
///   1. how fast each pair is closing, recorded before anything changes it, for the bounce
///   2. stop at the surface: a pair may close no faster than takes it to the surface by the end of dt, so a fast
///      body arrives at what it would have passed through. Iterated, so a body in several contacts at once
///      settles against all of them: each pass reads the velocities the last one left
///   3. bounce: a pair the solver pushed apart leaves at its restitution times the speed it came in at. Done apart
///      from 2, which on its own leaves a body arriving at the surface with next to no speed left to bounce
pub fn SolveVelocities(self: *CollisionManager, dt: f32) void {
    const zone = Tracy.ZoneInit("CollisionManager::SolveVelocities", @src());
    defer zone.Deinit();
    zone.Value(self._BlockingContacts.items.len);

    for (self._BlockingContacts.items) |*contact| {
        const q_rb_origin = contact.mOrigin.GetComponent(RigidBodyComponent);
        const q_rb_target = contact.mTarget.GetComponent(RigidBodyComponent);
        contact.mApproachSpeed = -RelativeNormalVelocity(contact.*, q_rb_origin, q_rb_target);
        contact.mImpulse = 0;
        contact.mBounce = 0;
    }

    for (0..SOLVER_ITERS) |_| {
        for (self._BlockingContacts.items) |*contact| {
            //either side can be a bare collider with no rigid body, which the solver treats as static
            const q_rb_origin = contact.mOrigin.GetComponent(RigidBodyComponent);
            const q_rb_target = contact.mTarget.GetComponent(RigidBodyComponent);

            if (InvMassOf(q_rb_origin) == 0 and InvMassOf(q_rb_target) == 0) continue;

            StopAtSurface(contact, q_rb_origin, q_rb_target, dt);
        }
    }

    for (self._BlockingContacts.items) |*contact| {
        const q_rb_origin = contact.mOrigin.GetComponent(RigidBodyComponent);
        const q_rb_target = contact.mTarget.GetComponent(RigidBodyComponent);

        if (InvMassOf(q_rb_origin) == 0 and InvMassOf(q_rb_target) == 0) continue;

        Bounce(contact, q_rb_origin, q_rb_target);
    }
}

/// For trigger pairs that are apart: whether the path the two take this substep goes into each other, which sets
/// mCrossed. A fast body can be short of a thin trigger on one substep and past it on the next without ever
/// being seen overlapping it, and nothing slows it down at a trigger the way the solver does at a solid surface.
/// Runs after SolveVelocities, so it sweeps along the velocities the bodies will really move with: a ball that
/// bounces off a wall does not count as going into the trigger behind it.
pub fn SweepTriggers(self: *CollisionManager, dt: f32) void {
    const zone = Tracy.ZoneInit("CollisionManager::SweepTriggers", @src());
    defer zone.Deinit();

    for (self._OverlapContacts.items) |*contact| {
        if (contact.mSeparation < 0.0) continue; //already overlapping, touching without a sweep

        //how far the target moves relative to the origin this substep
        const relative_velocity = VelocityOf(contact.mTarget, contact.mTarget.GetComponent(RigidBodyComponent)).SubVec(VelocityOf(contact.mOrigin, contact.mOrigin.GetComponent(RigidBodyComponent)));
        const motion = relative_velocity.MulScalar(dt);

        contact.mCrossed = Collisions.SweepShapes(
            contact,
            contact.mOrigin.GetComponent(EntityTransformComponent).?,
            contact.mOrigin.GetComponent(ColliderComponent).?,
            contact.mTarget.GetComponent(EntityTransformComponent).?,
            contact.mTarget.GetComponent(ColliderComponent).?,
            motion,
        );
    }
}

/// Moves bodies after they have moved by their velocities, then brings the transforms up to date. Two things,
/// both along the contact's normal:
///   - a pair that really overlaps is pushed apart, by the depth the narrow pass measured. Once: the depth is
///     never measured again here, so a second push would go the full depth again for overlap already removed
///   - a pair that bounced while still apart is moved back toward each other by (1 + restitution) x the gap.
///     The bounce set the leaving velocity for the whole substep, so the body would turn around that gap short
///     of the surface. Moving it back is the same as reaching the surface and bouncing for the time left over
pub fn CorrectPositions(self: *CollisionManager, world_manager: *WorldManager, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("CollisionManager::CorrectPositions", @src());
    defer zone.Deinit();

    for (self._BlockingContacts.items) |contact| {
        const q_rb_origin = contact.mOrigin.GetComponent(RigidBodyComponent);
        const q_rb_target = contact.mTarget.GetComponent(RigidBodyComponent);

        if (InvMassOf(q_rb_origin) == 0 and InvMassOf(q_rb_target) == 0) continue;

        //only one of these is ever above 0: the first needs an overlap, the second a gap
        const push_apart = @max(-contact.mSeparation - SLOP, 0.0) * PERCENT;
        const pull_together = if (contact.mBounce > 0.0) (1.0 + contact.mBounce) * @max(contact.mSeparation, 0.0) else 0.0;
        const distance = push_apart - pull_together;
        if (distance == 0.0) continue;

        try MoveAlongNormal(engine_context, contact, q_rb_origin, q_rb_target, distance);
    }
    try UpdateWorldTransforms(world_manager, engine_context);
}

pub fn PostsolverPass(self: *CollisionManager, engine_context: *EngineContext) !void {
    _ = engine_context;
    for (self._OverlapContacts.items) |contact| {
        _ = contact;
        //trigger a PostSolverEvent
    }
    for (self._BlockingContacts.items) |contact| {
        _ = contact;
        //trigger a PostSolverEvent
    }
}

pub fn EndPass(self: *CollisionManager, engine_context: *EngineContext) void {
    _ = engine_context;
    self._BlockingContacts.clearRetainingCapacity();
    self._OverlapContacts.clearRetainingCapacity();
}

fn GetCollisionType(collider_origin: *ColliderComponent, collider_target: *ColliderComponent) CollisionType {
    const intersection_a = collider_origin.mCollisionFilter.CategoryMask.intersectWith(collider_target.mCollisionFilter.RespondMask);
    const intersection_b = collider_target.mCollisionFilter.CategoryMask.intersectWith(collider_origin.mCollisionFilter.RespondMask);
    if (intersection_a.findFirstSet() == null or intersection_b.findFirstSet() == null) { //if either results in an empty bitset then they do not collide at all
        return .Ignore;
    }

    //if we get here we collide but we need to check trigger to see first

    if (collider_origin.mCollisionFilter.IsTrigger or collider_target.mCollisionFilter.IsTrigger) {
        return .Overlap;
    }

    return .Block;
}

/// A collider without a rigid body cannot be moved by the solver, which is exactly a static body
fn InvMassOf(q_rb: ?*RigidBodyComponent) f32 {
    return if (q_rb) |rb| rb._InvMass else 0.0;
}

/// A static body never moves, so whatever velocity it was given is not what it hits with
fn VelocityOf(entity: Entity, q_rb: ?*RigidBodyComponent) Vec3(f32) {
    const rb = q_rb orelse return std.mem.zeroes(Vec3(f32));
    if (entity.HasComponent(StaticBodyTag)) return std.mem.zeroes(Vec3(f32));
    return rb._Velocity;
}

/// A collider without a rigid body has no material, so it adds no bounce of its own
fn RestitutionOf(q_rb: ?*RigidBodyComponent) f32 {
    return if (q_rb) |rb| rb.mMaterialData.GetRestitution() else 0.0;
}

/// The bouncier of the two surfaces wins, so a bouncy ball bounces off anything without every wall
/// needing a material too
fn CombinedRestitution(q_rb_origin: ?*RigidBodyComponent, q_rb_target: ?*RigidBodyComponent) f32 {
    return @max(RestitutionOf(q_rb_origin), RestitutionOf(q_rb_target));
}

/// The target's velocity relative to the origin's along the normal: negative while they close
fn RelativeNormalVelocity(contact: Contact, q_rb_origin: ?*RigidBodyComponent, q_rb_target: ?*RigidBodyComponent) f32 {
    const relative_velocity = VelocityOf(contact.mTarget, q_rb_target).SubVec(VelocityOf(contact.mOrigin, q_rb_origin));
    return relative_velocity.Dot(contact.mNormal);
}

/// Pushes the pair apart along the normal with an impulse of `magnitude`, split by how pushable each side is.
/// Callers make sure at least one side has a nonzero inverse mass
fn ApplyNormalImpulse(contact: *Contact, q_rb_origin: ?*RigidBodyComponent, q_rb_target: ?*RigidBodyComponent, magnitude: f32) void {
    const impulse = contact.mNormal.MulScalar(magnitude);
    if (q_rb_origin) |rb_origin| rb_origin.ApplyImpulse(impulse.Neg());
    if (q_rb_target) |rb_target| rb_target.ApplyImpulse(impulse);
    contact.mImpulse += magnitude;
}

/// Takes away as much of the closing speed as would carry the pair past each other within dt. A pair still
/// apart may close its gap this substep and no more, so a fast body ends the substep at the surface rather
/// than through it. A pair already overlapping may not close at all.
/// Callers make sure at least one side has a nonzero inverse mass
fn StopAtSurface(contact: *Contact, q_rb_origin: ?*RigidBodyComponent, q_rb_target: ?*RigidBodyComponent, dt: f32) void {
    const normal_velocity = RelativeNormalVelocity(contact.*, q_rb_origin, q_rb_target);
    const allowed_closing = @max(contact.mSeparation, 0.0) / dt;
    if (normal_velocity >= -allowed_closing) return; //they won't get past the surface at this speed

    const magnitude = -(normal_velocity + allowed_closing) / (InvMassOf(q_rb_origin) + InvMassOf(q_rb_target));
    ApplyNormalImpulse(contact, q_rb_origin, q_rb_target, magnitude);
}

/// Sends a pair the solver stopped back apart at its restitution times the speed it was closing at before the
/// solver did anything: 0 leaves them stopped, 1 hands all of it back, which against an immovable side is a
/// mirror reflection about the normal. Only for pairs the solver actually pushed, so a near miss never bounces,
/// and only above RESTITUTION_THRESHOLD, so a resting body is not kept hopping.
/// Callers make sure at least one side has a nonzero inverse mass
fn Bounce(contact: *Contact, q_rb_origin: ?*RigidBodyComponent, q_rb_target: ?*RigidBodyComponent) void {
    if (contact.mImpulse <= 0.0 or contact.mApproachSpeed <= RESTITUTION_THRESHOLD) return;

    const restitution = CombinedRestitution(q_rb_origin, q_rb_target);
    if (restitution <= 0.0) return;

    const leaving_speed = restitution * contact.mApproachSpeed;
    const normal_velocity = RelativeNormalVelocity(contact.*, q_rb_origin, q_rb_target);
    if (normal_velocity >= leaving_speed) return;

    const magnitude = (leaving_speed - normal_velocity) / (InvMassOf(q_rb_origin) + InvMassOf(q_rb_target));
    ApplyNormalImpulse(contact, q_rb_origin, q_rb_target, magnitude);
    contact.mBounce = restitution;
}

/// Moves the pair `distance` further apart along the normal (toward each other when negative), split by how
/// pushable each side is. Callers make sure at least one side has a nonzero inverse mass
fn MoveAlongNormal(engine_context: *EngineContext, contact: Contact, q_rb_origin: ?*RigidBodyComponent, q_rb_target: ?*RigidBodyComponent, distance: f32) !void {
    const entity_origin = contact.mOrigin;
    const entity_target = contact.mTarget;
    const inv_mass_origin = InvMassOf(q_rb_origin);
    const inv_mass_target = InvMassOf(q_rb_target);

    const correction = contact.mNormal.MulScalar(distance / (inv_mass_origin + inv_mass_target));

    //an immovable side would get a zero offset, so it is skipped rather than written back unchanged,
    //which would still tag it dirty and send it through the next transform pass for nothing
    if (inv_mass_origin != 0) {
        const transform_origin = entity_origin.GetComponent(EntityTransformComponent).?;
        var origin_translation = transform_origin.GetTranslation();
        origin_translation.SubEqVec(correction.MulScalar(inv_mass_origin));
        try entity_origin.SetTranslation(engine_context, origin_translation);
    }

    if (inv_mass_target != 0) {
        const transform_target = entity_target.GetComponent(EntityTransformComponent).?;
        var target_translation = transform_target.GetTranslation();
        target_translation.AddEqVec(correction.MulScalar(inv_mass_target));
        try entity_target.SetTranslation(engine_context, target_translation);
    }
}

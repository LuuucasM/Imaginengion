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
const GroupQuery = @import("../ECS/ECSManager.zig").GroupQuery;
const Entity = @import("../ECSObjects/Entity.zig");
const WorldManager = @import("../Core/WorldManager.zig");
const SkipField = @import("../Core/SkipField.zig").StaticSkipField;
const UpdateWorldTransforms = @import("PhysicsManager.zig").UpdateWorldTransforms;
const CollisionType = @import("Collisions.zig").CollisionType;
const MathTypes = @import("../Math/MathTypes.zig");
const Vec3 = MathTypes.Vec3;
const ImguiManager = @import("../Imgui/Imgui.zig");

const ColliderQuery = GroupQuery{ .Component = ColliderComponent };
const DynamicQuery = GroupQuery{ .Component = DynamicBodyTag };

//colliders the solver can actually move
pub const DynamicCollidersQuery = GroupQuery{ .And = &.{ ColliderQuery, DynamicQuery } };

//everything else that collides: static bodies, and colliders carrying no RigidBodyComponent at
//all. Asking for "collider and not dynamic" rather than "collider and static" is deliberate, so
//that a collider with no rigid body (which has neither body tag) still takes part in collision
//the way it does today, instead of silently dropping out of the broad pass.
pub const OtherCollidersQuery = GroupQuery{ .Not = .{ .mFirst = &ColliderQuery, .mSecond = &DynamicQuery } };

const SOLVER_ITERS: u32 = 4;
const PERCENT: f32 = 0.8;
const SLOP: f32 = 0.01;

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
/// dynamic_arr and other_arr are the DynamicCollidersQuery and OtherCollidersQuery groups, fetched
/// once by the caller for every substep rather than re-queried here each time.
pub fn BroadPass(self: *CollisionManager, engine_context: *EngineContext, world_manager: *WorldManager, dynamic_arr: []const Entity.Type, other_arr: []const Entity.Type) !void {
    const zone = Tracy.ZoneInit("CollisionManager::BroadPass", @src());
    defer zone.Deinit();

    //a pair that neither side can move has nothing for the solver to do with it, so those pairs are
    //never built rather than being built, classified, narrow-phase tested and then dropped at the
    //_InvMass check in SolverPass. Every remaining pair has at least one dynamic body in it, which
    //is why both loops below are anchored on the dynamic list.
    for (0..dynamic_arr.len) |i| {
        for (i + 1..dynamic_arr.len) |j| {
            try self.AddBroadPair(engine_context, world_manager, dynamic_arr[i], dynamic_arr[j]);
        }
    }

    for (dynamic_arr) |origin_id| {
        for (other_arr) |target_id| {
            try self.AddBroadPair(engine_context, world_manager, origin_id, target_id);
        }
    }

    Tracy.Plot("Physics/Broad Pairs", .{ .color = 0x795548 }, self._BlockingContacts.items.len + self._OverlapContacts.items.len);
}

/// Classifies one pair and records it if the two can interact at all.
fn AddBroadPair(self: *CollisionManager, engine_context: *EngineContext, world_manager: *WorldManager, origin_id: Entity.Type, target_id: Entity.Type) !void {
    const entity_origin = world_manager.GetEntity(origin_id);
    const entity_target = world_manager.GetEntity(target_id);

    const collider_origin = entity_origin.GetComponent(ColliderComponent).?;
    const collider_target = entity_target.GetComponent(ColliderComponent).?;

    const collision_type = GetCollisionType(collider_origin, collider_target);

    if (collision_type == .Ignore) return;

    const contact: Contact = .{
        .mOrigin = entity_origin,
        .mTarget = entity_target,
        .mNormal = Vec3(f32){ .x = 0, .y = 0, .z = 0 },
        .mPenetration = 0,
    };

    switch (collision_type) {
        .Block => try self._BlockingContacts.append(engine_context.EngineAllocator(), contact),
        .Overlap => try self._OverlapContacts.append(engine_context.EngineAllocator(), contact),
        .Ignore => unreachable,
    }
}

///Checks generated contacts list from broad pass to see if thing actually collided
/// For the contact sets the penetration, normal, and contact state
pub fn NarrowPass(self: *CollisionManager, engine_context: *EngineContext) !void {
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

        if (Collisions.TestShapes(contact, origin_transform, collider_origin, target_transform, collider_target)) {
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

        if (Collisions.TestShapes(contact, origin_transform, collider_origin, target_transform, collider_target)) {
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

    try self.UpdateTouching(engine_context);
}

/// Works out which of this substep's contacts are new and queues a CollisionBeginEvent for each.
/// Runs on what the narrow pass left, so every contact in both lists is a pair that really overlaps.
fn UpdateTouching(self: *CollisionManager, engine_context: *EngineContext) !void {
    const engine_allocator = engine_context.EngineAllocator();

    self._TouchingNow.clearRetainingCapacity();
    try self._TouchingNow.ensureTotalCapacity(engine_allocator, self._BlockingContacts.items.len + self._OverlapContacts.items.len);
    for (self._BlockingContacts.items, 0..) |contact, contact_ind| {
        self._TouchingNow.appendAssumeCapacity(.{ .mKey = PairKey(contact.mOrigin.mID, contact.mTarget.mID), .mContactInd = @intCast(contact_ind), .mIsTrigger = false });
    }
    for (self._OverlapContacts.items, 0..) |contact, contact_ind| {
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
        try engine_context.mGameEventManager.Insert(engine_allocator, .PostPhysics, .{ .CollisionBeginEvent = .{
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

pub fn SolverPass(self: *CollisionManager, world_manager: *WorldManager, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("CollisionManager::SolverPass", @src());
    defer zone.Deinit();
    zone.Value(self._BlockingContacts.items.len);

    //velocities are iterated so a body in several contacts at once settles against all of them: each
    //pass reads the velocities the last one left, which is still current
    for (0..SOLVER_ITERS) |_| {
        for (self._BlockingContacts.items) |contact| {
            //either side can be a bare collider with no rigid body, which the solver treats as static
            const q_rb_origin = contact.mOrigin.GetComponent(RigidBodyComponent);
            const q_rb_target = contact.mTarget.GetComponent(RigidBodyComponent);

            if (InvMassOf(q_rb_origin) == 0 and InvMassOf(q_rb_target) == 0) continue;

            VelocityCorrection(contact, q_rb_origin, q_rb_target);
        }
    }

    //positions are corrected once. mPenetration was measured by the narrow pass and is never
    //re-measured here, so a second pass would push by the full depth again for overlap already removed
    for (self._BlockingContacts.items) |contact| {
        const q_rb_origin = contact.mOrigin.GetComponent(RigidBodyComponent);
        const q_rb_target = contact.mTarget.GetComponent(RigidBodyComponent);

        if (InvMassOf(q_rb_origin) == 0 and InvMassOf(q_rb_target) == 0) continue;

        try PositionCorrection(engine_context, contact, contact.mOrigin, q_rb_origin, contact.mTarget, q_rb_target);
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

fn VelocityOf(q_rb: ?*RigidBodyComponent) Vec3(f32) {
    return if (q_rb) |rb| rb._Velocity else std.mem.zeroes(Vec3(f32));
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

/// Callers make sure at least one side has a nonzero inverse mass
fn VelocityCorrection(contact: Contact, q_rb_origin: ?*RigidBodyComponent, q_rb_target: ?*RigidBodyComponent) void {
    const rv = VelocityOf(q_rb_target).SubVec(VelocityOf(q_rb_origin));

    const vel_along_norm = rv.Dot(contact.mNormal);
    if (vel_along_norm > 0) return; //they are already moving apart

    //coefficient of restitution: 0 kills the closing speed, 1 hands all of it back the other way,
    //which against an immovable side is a mirror reflection about the normal
    const e: f32 = if (-vel_along_norm > RESTITUTION_THRESHOLD) CombinedRestitution(q_rb_origin, q_rb_target) else 0.0;

    const j = (-(1.0 + e) * vel_along_norm) / (InvMassOf(q_rb_origin) + InvMassOf(q_rb_target)); //magnitude of the impulse

    const impulse = contact.mNormal.MulScalar(j);

    if (q_rb_origin) |rb_origin| rb_origin.ApplyImpulse(impulse.Neg());
    if (q_rb_target) |rb_target| rb_target.ApplyImpulse(impulse);
}

/// Callers make sure at least one side has a nonzero inverse mass
fn PositionCorrection(engine_context: *EngineContext, contact: Contact, entity_origin: Entity, q_rb_origin: ?*RigidBodyComponent, entity_target: Entity, q_rb_target: ?*RigidBodyComponent) !void {
    const inv_mass_origin = InvMassOf(q_rb_origin);
    const inv_mass_target = InvMassOf(q_rb_target);

    const correction_mag = (@max(contact.mPenetration - SLOP, 0.0)) / (inv_mass_origin + inv_mass_target) * PERCENT;
    const correction = contact.mNormal.MulScalar(correction_mag);

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

const std = @import("std");
const Collisions = @import("Collisions.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const Tracy = @import("../Core/Tracy.zig");
const Contact = Collisions.Contact;
const EntityComponents = @import("../GameObjects/Components.zig");
const ColliderComponent = EntityComponents.ColliderComponent;
const EntityTransformComponent = EntityComponents.TransformComponent;
const RigidBodyComponent = EntityComponents.RigidBodyComponent;
const Entity = @import("../GameObjects/Entity.zig");
const SceneManager = @import("../Scene/SceneManager.zig");
const SkipField = @import("../Core/SkipField.zig").StaticSkipField;
const UpdateWorldTransforms = @import("PhysicsManager.zig").UpdateWorldTransforms;
const CollisionType = @import("Collisions.zig").CollisionType;
const MathTypes = @import("../Math/MathTypes.zig");
const Vec3 = MathTypes.Vec3;
const Set = @import("../Vendor/ziglang-set/src/array_hash_set/unmanaged.zig").ArraySetUnmanaged;

const SOLVER_ITERS: u32 = 4;
const PERCENT: f32 = 0.8;
const SLOP: f32 = 0.01;

const CollisionManager = @This();

const CurrCollisionSet = Set(u64);

pub const CollisionFilter = struct {
    pub const default: CollisionFilter = .{
        .IsTrigger = false,
        .CategoryMask = .empty,
        .RespondMask = .empty,
    };
    IsTrigger: bool,
    CategoryMask: std.StaticBitSet(32),
    RespondMask: std.StaticBitSet(32),
};

pub const empty: CollisionManager = .{
    ._Contacts = .empty,
    ._ContactCache1 = .empty,
    ._ContactCache2 = .empty,
    ._LastCache = undefined,
    ._CurrentCache = undefined,
};

pub const ContactCache = struct {
    pub const empty: ContactCache = .{
        .AccumImpulse = 0.0,
    };
    AccumImpulse: f32,
};

_LastCache: std.AutoArrayHashMapUnmanaged(u64, ContactCache),
_CurrentCache: std.AutoArrayHashMapUnmanaged(u64, ContactCache),
_BlockingContacts: std.ArrayList(Contact),
_OverlapContacts: std.ArrayList(Contact),

pub fn Init(_: *CollisionManager, _: std.mem.Allocator) !void {}

pub fn Deinit(self: *CollisionManager, engine_allocator: std.mem.Allocator) void {
    self._BlockingContacts.deinit(engine_allocator);
    self._OverlapContacts.deinit(engine_allocator);
}

pub fn Reset(self: *CollisionManager, engine_allocator: std.mem.Allocator) void {
    self._BlockingContacts.clearAndFree(engine_allocator);
    self._OverlapContacts.clearAndFree(engine_allocator);
}

///Checks the whole scene for objects that can possibly collide.
/// For the contact sets the entity origin, target, and collision type.
pub fn BroadPass(self: *CollisionManager, engine_context: *EngineContext, scene_manager: *SceneManager) !void {
    const zone = Tracy.ZoneInit("CollisionManager::BroadPassf", @src());
    defer zone.Deinit();

    const colliders_arr = try scene_manager.GetEntityGroup(engine_context.FrameAllocator(), .{ .Component = ColliderComponent });

    for (0..colliders_arr.items.len) |i| {
        const entity_origin = scene_manager.GetEntity(colliders_arr.items[i]);
        for (i + 1..colliders_arr.items.len) |j| {
            const entity_target = scene_manager.GetEntity(colliders_arr.items[j]);

            const collider_origin = entity_origin.GetComponent(ColliderComponent).?;
            const collider_target = entity_target.GetComponent(ColliderComponent).?;

            const collision_type = GetCollisionType(collider_origin, collider_target);

            if (collision_type == .Ignore) continue;

            const contact: Contact = .{
                .mOrigin = entity_origin,
                .mTarget = entity_target,
                .mNormal = Vec3(f32){ .x = 0, .y = 0, .z = 0 },
                .mPenetration = 0,
            };

            switch (collision_type) {
                .Block => {
                    try self._BlockingContacts.append(engine_context.EngineAllocator(), contact);
                },
                .Overlap => {
                    try self._OverlapContacts.append(engine_context.EngineAllocator(), contact);
                },
                .Ignore => unreachable,
            }
        }
    }
}

///Checks generated contacts list from broad pass to see if thing actually collided
/// For the contact sets the penetration, normal, and contact state
pub fn NarrowPass(self: *CollisionManager, engine_context: *EngineContext) !void {
    var i: usize = 0;
    var end: usize = self._OverlapContacts.items.len;
    while (i < end) {
        const contact = self._OverlapContacts.items[i];
        const collider_origin = contact.mOrigin.GetComponent(ColliderComponent).?;
        const collider_target = contact.mTarget.GetComponent(ColliderComponent).?;

        const origin_transform = contact.mOrigin.GetComponent(EntityTransformComponent).?;
        const target_transform = contact.mTarget.GetComponent(EntityTransformComponent).?;

        if (std.meta.activeTag(collider_origin.mShape) == .Sphere and std.meta.activeTag(collider_target.mShape) == .Sphere) {
            Collisions.SphereSphere(contact, origin_transform, target_transform);
            i += 1;
        } else if (std.meta.activeTag(collider_origin.mShape) == .Box and std.meta.activeTag(collider_target.mShape) == .Box) {
            Collisions.BoxBox(contact, origin_transform, target_transform);
            i += 1;
        } else {
            self._OverlapContacts.items[i] = self._OverlapContacts.items[end - 1];
            end -= 1;
        }
    }
    self._OverlapContacts.items.len = end;

    i = 0;
    end = self._BlockingContacts.item.len;
    while (i < end) {
        const contact = self._BlockingContacts.items[i];
        const collider_origin = contact.mOrigin.GetComponent(ColliderComponent).?;
        const collider_target = contact.mTarget.GetComponent(ColliderComponent).?;

        const origin_transform = contact.mOrigin.GetComponent(EntityTransformComponent).?;
        const target_transform = contact.mTarget.GetComponent(EntityTransformComponent).?;

        if (std.meta.activeTag(collider_origin.mShape) == .Sphere and std.meta.activeTag(collider_target.mShape) == .Sphere) {
            Collisions.SphereSphere(contact, origin_transform, target_transform);
            i += 1;
        } else if (std.meta.activeTag(collider_origin.mShape) == .Box and std.meta.activeTag(collider_target.mShape) == .Box) {
            Collisions.BoxBox(contact, origin_transform, target_transform);
            i += 1;
        } else {
            self._BlockingContacts.items[i] = self._BlockingContacts.items[end - 1];
            end -= 1;
        }
    }
    self._BlockingContacts.items.len = end;

    //check for begin collision events
    for (self._OverlapContacts.items) |contact| {
        const key: u64 = @as(u64, @intCast(contact.mOrigin.mEntityID)) << 32 | @as(u64, @intCast(contact.mTarget.mEntityID));
        self._CurrentCache.put(engine_context.FrameAllocator(), key, .empty);
        if (!self._LastCache.contains(key)) {
            //create new BeginCollisionEvent
        }
    }
    for (self._BlockingContacts.items) |contact| {
        const key: u64 = @as(u64, @intCast(contact.mOrigin.mEntityID)) << 32 | @as(u64, @intCast(contact.mTarget.mEntityID));
        self._CurrentCache.put(engine_context.FrameAllocator(), key, .empty);
        if (!self._LastCache.contains(key)) {
            //create new BeginCollisionEvent
        }
    }

    //check for end collision events
    const prev_iter = self._LastCache.iterator();
    while (prev_iter.next()) |entry| {
        if (!self._CurrentCache.contains(entry.key_ptr.*)) {
            //create a new EndCOllisionEvent
        }
    }
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

pub fn SolverPass(self: *CollisionManager, comptime world_type: EngineContext.WorldType, engine_context: *EngineContext) !void {
    for (0..SOLVER_ITERS) |_| {
        for (self._BlockingContacts.items) |contact| {
            const entity_origin = contact.mOrigin;
            const entity_target = contact.mTarget;

            const q_rb_origin = entity_origin.GetComponent(RigidBodyComponent);
            const q_rb_target = entity_target.GetComponent(RigidBodyComponent);

            if (q_rb_origin) |rb_origin| {
                if (q_rb_target) |rb_target| {
                    if (rb_origin._InvMass == 0 and rb_target._InvMass == 0) continue;

                    VelocityCorrection(contact, rb_origin, rb_target);
                    PositionCorrection(contact, entity_origin, rb_origin, entity_target, rb_target);
                }
            }
        }
        try UpdateWorldTransforms(world_type, engine_context);
    }
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

pub fn EndPass(self: *CollisionManager, engine_context: *EngineContext) !void {
    self._LastCache.deinit(engine_context.EngineAllocator());
    self._LastCache = self._CurrentCache;
    self._CurrentCache = .empty;
    self._BlockingContacts.clearAndFree(engine_context.EngineAllocator());
    self._OverlapContacts.clearAndFree(engine_context.EngineAllocator());
}

fn GetCollisionType(collider_origin: *ColliderComponent, collider_target: *ColliderComponent) CollisionType {
    const intersection_a = collider_origin.mCollisionFilter.CategoryMask.intersectWith(collider_target.mCollisionFilter.RespondMask);
    const intersection_b = collider_target.mCollisionFilter.CategoryMask.intersectWith(collider_origin.mCollisionFilter.RespondMask);
    if (intersection_a.findFirstSet == null or intersection_b.findFirstSet == null) { //if either results in an empty bitset then they do not collide at all
        return .Ignore;
    }

    //if we get here we collide but we need to check trigger to see first

    if (collider_origin.mCollisionFilter.IsTrigger or collider_target.mCollisionFilter.IsTrigger) {
        return .Overlap;
    }

    return .Block;
}

fn VelocityCorrection(contact: Contact, rb_origin: *RigidBodyComponent, rb_target: *RigidBodyComponent) void {
    const zone = Tracy.ZoneInit("CollisionManager::ResolveCollisions", @src());
    defer zone.Deinit();
    const rv = rb_target._Velocity.SubVec(rb_origin._Velocity);

    const vel_along_norm = rv.Dot(contact.mNormal);
    if (vel_along_norm > 0) return; //they are already moving apart

    const e: f32 = 0.0; //coefficient of restitution

    const j = (-(1.0 + e) * vel_along_norm) / (rb_origin._InvMass + rb_target._InvMass); //magnitude of the impulse

    const impulse = contact.mNormal.MulScalar(j);

    rb_origin.ApplyImpulse(impulse.Neg());
    rb_target.ApplyImpulse(impulse);
}

fn PositionCorrection(contact: Contact, entity_origin: Entity, rb_origin: *RigidBodyComponent, entity_target: Entity, rb_target: *RigidBodyComponent) void {
    const zone = Tracy.ZoneInit("CollisionManager::PositionCorrection", @src());
    defer zone.Deinit();
    const correction_mag = (@max(contact.mPenetration - SLOP, 0.0)) / (rb_origin._InvMass + rb_target._InvMass) * PERCENT;
    const correction = contact.mNormal.MulScalar(correction_mag);

    const transform_origin = entity_origin.GetComponent(EntityTransformComponent).?;
    const transform_target = entity_target.GetComponent(EntityTransformComponent).?;

    transform_origin.Translation.SubEqVec(correction.MulScalar(rb_origin._InvMass));
    transform_target.Translation.AddEqVec(correction.MulScalar(rb_target._InvMass));
}

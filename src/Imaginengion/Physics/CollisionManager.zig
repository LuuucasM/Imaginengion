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

const SOLVER_ITERS: u32 = 4;
const PERCENT: f32 = 0.8;
const SLOP: f32 = 0.01;

const CollisionManager = @This();

pub const CollisionType = enum {
    Ignore,
    Overlap,
    Block,
};

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
};

pub const ContactCache = struct {
    pub const empty: ContactCache = .{
        .AccumImpulse = 0.0,
    };
    AccumImpulse: f32,
};

_ContactCache1: std.AutoHashMapUnmanaged(u64, ContactCache),
_ContactCache2: std.AutoHashMapUnmanaged(u64, ContactCache),
_LastCache: *std.AutoHashMapUnmanaged(u64, ContactCache),
_CurrentCache: *std.AutoHashMapUnmanaged(u64, ContactCache),
_Contacts: std.ArrayList(Contact),

pub fn Init(self: *CollisionManager, _: std.mem.Allocator) !void {
    self._CurrentCache = &self._ContactCache2;
    self._LastCache = &self._ContactCache1;
}

pub fn Deinit(self: *CollisionManager, engine_allocator: std.mem.Allocator) void {
    self._Contacts.deinit(engine_allocator);
}

pub fn Reset(self: *CollisionManager, engine_allocator: std.mem.Allocator) void {
    self._Contacts.clearAndFree(engine_allocator);
}

pub fn StartFrame(self: *CollisionManager, engine_allocator: std.mem.Allocator) void {
    const tmp = self._CurrentCache;
    self._CurrentCache = self._LastCache;
    self._LastCache = tmp;
    self._CurrentCache.clearAndFree(engine_allocator);
}

pub fn DetectCollisions(self: CollisionManager, engine_context: *EngineContext, scene_manager: *SceneManager) !void {
    const zone = Tracy.ZoneInit("CollisionManager::DetectCollisions", @src());
    defer zone.Deinit();

    const colliders_arr = try scene_manager.GetEntityGroup(engine_context.FrameAllocator(), .{ .Component = ColliderComponent });

    for (0..colliders_arr.items.len) |i| {
        const entity_origin = scene_manager.GetEntity(colliders_arr.items[i]);
        for (i + 1..colliders_arr.items.len) |j| {
            const entity_target = scene_manager.GetEntity(colliders_arr.items[j]);

            const collider_origin = entity_origin.GetComponent(ColliderComponent).?;
            const collider_target = entity_target.GetComponent(ColliderComponent).?;

            const collision_type = GetCollisionType(collider_origin, collider_target);

            if (collision_type == .Ignore) {
                continue;
            }

            var contact: ?Contact = blk: {
                if (std.meta.activeTag(collider_origin.mShape) == .Sphere and std.meta.activeTag(collider_target.mShape) == .Sphere) {
                    const origin_transform = entity_origin.GetComponent(EntityTransformComponent).?;
                    const target_transform = entity_target.GetComponent(EntityTransformComponent).?;
                    break :blk Collisions.SphereSphere(
                        origin_transform.GetWorldPosition(),
                        origin_transform.GetWorldScale(),
                        target_transform.GetWorldPosition(),
                        target_transform.GetWorldScale(),
                    );
                } else if (std.meta.activeTag(collider_origin.mShape) == .Box and std.meta.activeTag(collider_target.mShape) == .Box) {
                    const origin_transform = entity_origin.GetComponent(EntityTransformComponent).?;
                    const target_transform = entity_target.GetComponent(EntityTransformComponent).?;
                    break :blk Collisions.BoxBox(
                        origin_transform.GetWorldPosition(),
                        origin_transform.GetWorldScale(),
                        target_transform.GetWorldPosition(),
                        target_transform.GetWorldScale(),
                    );
                } else {
                    std.log.err("Cannot handle collision type between {s} and {s} yet!\n", .{ @tagName(collider_origin.mShape), @tagName(collider_target.mShape) });
                    break :blk null;
                }
            };

            if (contact) {
                contact.?.mContactType = collision_type;
                contact.?.mOrigin = entity_origin;
                contact.?.mTarget = entity_target;

                const key: u64 = @as(u64, @intCast(entity_origin.mEntityID)) << 32 | @as(u64, @intCast(entity_target));

                if (self._CurrentCache.get(key) == null) {
                    try self._CurrentCache.put(engine_context.EngineAllocator(), key, .empty);

                    if (self._LastCache.get(key) == null) {
                        //TODO: BeginContact event
                    }
                }
                try self._Contacts.append(engine_context.EngineAllocator(), contact.?);
            }
        }
    }
}

pub fn ResolveCollisions(self: CollisionManager, comptime world_type: EngineContext.WorldType, engine_context: *EngineContext) void {
    //TODO: Pre-Solve events
    for (0..SOLVER_ITERS) |_| {
        for (self._Contacts.items) |contact| {
            const entity_origin = contact.mOrigin;
            const entity_target = contact.mTarget;

            if (contact.mContactType == .Block) {
                const q_rb_origin = entity_origin.GetComponent(RigidBodyComponent);
                const q_rb_target = entity_target.GetComponent(RigidBodyComponent);

                if (q_rb_origin) |rb_origin| {
                    if (q_rb_target) |rb_target| {
                        if (rb_origin._InvMass == 0 and rb_target._InvMass == 0) continue;

                        VelocityCorrection(contact, rb_origin, rb_target);
                        PositionCorrection(contact, entity_origin, rb_origin, entity_target, rb_target);
                    }
                }
            } else if (contact.mContactType == .Overlap) {
                //only trigger event
            }
        }
        try UpdateWorldTransforms(world_type, engine_context);
    }

    //TODO: Post-Solve Events
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

fn GetContact() ?Contact {}

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

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

pub const ChannelEnum = enum(u32) {
    None = 0,
    _,
};

pub const CollisionResponse = enum {
    Ignore,
    Overlap,
    Block,
};

pub const empty: CollisionManager = .{
    ._NextID = .NoSkip,
    ._Contacts = .empty,
    ._ChannelNameToID = .empty,
};

_NextID: SkipField(64), //64 is random number
_Contacts: std.ArrayList(Contact),
_ChannelNameToID: std.StringHashMapUnmanaged([]const u8, usize),

pub fn Init(self: *CollisionManager, engine_allocator: std.mem.Allocator) !void {
    try self._ChannelNameToID.ensureTotalCapacity(engine_allocator, 64 * 2); //NOTE: this 64 is to match the SkipField
}

pub fn Deinit(self: *CollisionManager, engine_allocator: std.mem.Allocator) void {
    self._Contacts.deinit(engine_allocator);
    self._ChannelNameToID.deinit(engine_allocator);
}

pub fn Reset(self: *CollisionManager, engine_allocator: std.mem.Allocator) void {
    self._Contacts.clearAndFree(engine_allocator);
}

pub fn DetectCollisions(self: CollisionManager, engine_context: *EngineContext, scene_manager: *SceneManager) !void {
    const zone = Tracy.ZoneInit("PhysicsManager::DetectCollisions", @src());
    defer zone.Deinit();

    const colliders_arr = try scene_manager.GetEntityGroup(engine_context.FrameAllocator(), .{ .Component = ColliderComponent });

    for (0..colliders_arr.items.len) |i| {
        const entity_origin = scene_manager.GetEntity(colliders_arr.items[i]);
        for (i + 1..colliders_arr.items.len) |j| {
            const entity_target = scene_manager.GetEntity(colliders_arr.items[j]);

            const collider_origin = entity_origin.GetComponent(ColliderComponent).?;
            const collider_target = entity_target.GetComponent(ColliderComponent).?;

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
                contact.?.mOrigin = entity_origin;
                contact.?.mTarget = entity_target;

                try self._Contacts.append(engine_context.EngineAllocator(), contact.?);
            }
        }
    }
}

pub fn ResolveCollisions(self: CollisionManager, comptime world_type: EngineContext.WorldType, engine_context: *EngineContext) void {
    for (0..SOLVER_ITERS) |_| {
        for (self._Contacts.items) |contact| {
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

fn VelocityCorrection(contact: Contact, rb_origin: *RigidBodyComponent, rb_target: *RigidBodyComponent) void {
    const zone = Tracy.ZoneInit("PhysicsManager::ResolveCollisions", @src());
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
    const zone = Tracy.ZoneInit("PhysicsManager::PositionCorrection", @src());
    defer zone.Deinit();
    const correction_mag = (@max(contact.mPenetration - SLOP, 0.0)) / (rb_origin._InvMass + rb_target._InvMass) * PERCENT;
    const correction = contact.mNormal.MulScalar(correction_mag);

    const transform_origin = entity_origin.GetComponent(EntityTransformComponent).?;
    const transform_target = entity_target.GetComponent(EntityTransformComponent).?;

    transform_origin.Translation.SubEqVec(correction.MulScalar(rb_origin._InvMass));
    transform_target.Translation.AddEqVec(correction.MulScalar(rb_target._InvMass));
}

pub fn RegisterChannel(self: *CollisionManager, name: []const u8) usize {
    if (self._ChannelNameToID.get(name)) |id| {
        return id;
    } else {
        const new_id = self._NextID.GetFirstUnskipped();
        self._ChannelNameToID.putAssumeCapacity(name, new_id);
        self._NextID.ChangeToSkipped(new_id);
        return new_id;
    }
}

pub fn RemoveChannel(self: *CollisionManager, name: []const u8) void {
    _ = self._ChannelNameToID.remove(name);
}

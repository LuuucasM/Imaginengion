const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const SceneManager = @import("../Scene/SceneManager.zig");

const Entity = @import("../GameObjects/Entity.zig");

const EntityComponents = @import("../GameObjects/Components.zig");
const RigidBodyComponent = EntityComponents.RigidBodyComponent;
const ColliderComponent = EntityComponents.ColliderComponent;
const EntitySceneComponent = EntityComponents.SceneIDComponent;
const EntityTransformComponent = EntityComponents.TransformComponent;
const ChildComponent = @import("../ECS/Components.zig").ChildComponent(Entity.Type);
const ParentComponent = @import("../ECS/Components.zig").ParentComponent(Entity.Type);

const SceneComponents = @import("../Scene/SceneComponents.zig");
const ScenePhysicsComponent = SceneComponents.PhysicsComponent;

const LinAlg = @import("../Math/LinAlg.zig");
const Vec3f32 = LinAlg.Vec3f32;
const Quatf32 = LinAlg.Quatf32;

const Collisions = @import("Collisions.zig");
const Contact = Collisions.Contact;

const PhysicsManager = @This();

const InternalData = struct {
    Accumulator: f32 = 0,
    Contacts: std.ArrayList(Contact) = .{},
};
const PHYSICS_DT = 1 / 60;
const PERCENT = 0.8;
const SLOP = 0.01;
const SOLVER_ITERS = 4;
const SUB_STEPS = 2;
const SUB_STEP_DT = PHYSICS_DT / SUB_STEPS;

_InternalData: InternalData = .{},

pub fn OnUpdate(self: *PhysicsManager, engine_context: *EngineContext, scene_manager: *SceneManager) !void {
    self._InternalData.Accumulator += engine_context.mDT;

    const rigid_body_arr = try scene_manager.GetEntityGroup(engine_context.FrameAllocator(), .{ .Component = RigidBodyComponent });

    while (self._InternalData.Accumulator >= PHYSICS_DT) : (self._InternalData.Accumulator -= PHYSICS_DT) {
        for (0..SUB_STEPS) |_| {
            for (rigid_body_arr.items) |entity_id| {
                const entity = scene_manager.GetEntity(entity_id);
                const entity_rb = entity.GetComponent(RigidBodyComponent).?;

                ApplyForces(entity, scene_manager, entity_rb);

                IntegrateVelocities(entity_rb, SUB_STEP_DT);
                IntegratePositions(entity, entity_rb, SUB_STEP_DT);
            }

            try self.DetectCollisions(engine_context, scene_manager);

            for (0..SOLVER_ITERS) |_| {
                for (self._InternalData.Contacts.items) |contact| {
                    const entity_origin = contact.mOrigin;
                    const entity_target = contact.mTarget;

                    const q_rb_origin = entity_origin.GetComponent(RigidBodyComponent);
                    const q_rb_target = entity_target.GetComponent(RigidBodyComponent);

                    if (q_rb_origin) |rb_origin| {
                        if (q_rb_target) |rb_target| {
                            if (rb_origin.mInvMass == 0 and rb_target.mInvMass == 0) continue;

                            ResolveCollisions(contact, rb_origin, rb_target);
                            PositionCorrection(contact, entity_origin, rb_origin, entity_target, rb_target);
                        }
                    }
                }
            }
            self._InternalData.Contacts.clearRetainingCapacity();
        }
    }
}

pub fn UpdateWorldTransforms(_: *PhysicsManager, engine_context: *EngineContext, scene_manager: *SceneManager) !void {
    const transforms_arr = try scene_manager.GetEntityGroup(engine_context.FrameAllocator(), .{ .Not = .{ .mFirst = .{ .Component = EntityTransformComponent }, .mSecond = .{ .Component = ChildComponent } } });

    for (transforms_arr.items) |entity_id| {
        const entity = scene_manager.GetEntity(entity_id);

        const transform = entity.GetComponent(EntityTransformComponent).?;

        transform.SetWorldPosition(transform.Translation);
        transform.SetWorldRotation(transform.Rotation);
        transform.SetWorldScale(transform.Scale);

        if (entity.GetComponent(ParentComponent)) |parent_component| {
            _ = parent_component;
            CalculateChildren(entity, transform.GetWorldPosition(), transform.GetWorldRotation(), transform.GetWorldScale());
        }
    }
}

fn CalculateChildren(parent_entity: Entity, position_acc: Vec3f32, rotation_acc: Quatf32, scale_acc: Vec3f32) void {
    const parent_component = parent_entity.GetComponent(ParentComponent).?;

    var curr_id = parent_component.mFirstChild;

    while (true) : (if (curr_id == parent_component.mFirstChild) break) {
        const child_entity = Entity{ .mEntityID = curr_id, .mECSManagerRef = parent_entity.mECSManagerRef };

        CalculateChildTransform(child_entity, position_acc, rotation_acc, scale_acc);

        const child_component = child_entity.GetComponent(ChildComponent).?;
        curr_id = child_component.mNext;
    }
}

fn CalculateChildTransform(child_entity: Entity, position_acc: Vec3f32, rotation_acc: Quatf32, scale_acc: Vec3f32) void {
    const transform = child_entity.GetComponent(EntityTransformComponent).?;

    transform.SetWorldPosition(transform.Translation + position_acc);
    transform.SetWorldRotation(LinAlg.QuatMulQuat(transform.Rotation, rotation_acc));
    transform.SetWorldScale(transform.Scale + scale_acc);

    if (child_entity.GetComponent(ParentComponent)) |parent_component| {
        _ = parent_component;
        CalculateChildren(child_entity, transform.GetWorldPosition(), transform.GetWorldRotation(), transform.GetWorldScale());
    }
}

fn ApplyForces(entity: Entity, scene_manager: *SceneManager, entity_rb: *RigidBodyComponent) void {
    const entity_scene_comp = entity.GetComponent(EntitySceneComponent).?;
    const scene_layer = scene_manager.GetSceneLayer(entity_scene_comp.SceneID);
    if (scene_layer.GetComponent(ScenePhysicsComponent)) |physics_component| {
        entity_rb.mForce += if (entity_rb.mInvMass != 0) physics_component.mGravity * @as(Vec3f32, @splat(entity_rb.mMass)) else @as(Vec3f32, @splat(0));
    } else {
        entity_rb.mForce += @as(Vec3f32, @splat(0 * entity_rb.mMass));
    }
}

fn IntegrateVelocities(entity_rb: *RigidBodyComponent, dt: f32) void {
    entity_rb.mVelocity += entity_rb.mForce * @as(Vec3f32, @splat(entity_rb.mInvMass * dt));
    entity_rb.mForce = std.mem.zeroes(Vec3f32);
}

fn IntegratePositions(entity: Entity, entity_rb: *RigidBodyComponent, dt: f32) void {
    const transform = entity.GetComponent(EntityTransformComponent).?;
    transform.Translation += entity_rb.mVelocity * @as(Vec3f32, @splat(dt));
}

fn DetectCollisions(self: *PhysicsManager, engine_context: *EngineContext, scene_manager: *SceneManager) !void {
    const colliders_arr = try scene_manager.GetEntityGroup(engine_context.FrameAllocator(), .{ .Component = ColliderComponent });

    for (0..colliders_arr.items.len) |i| {
        const entity_origin = scene_manager.GetEntity(colliders_arr.items[i]);
        for (i + 1..colliders_arr.items.len) |j| {
            const entity_target = scene_manager.GetEntity(colliders_arr.items[j]);

            const collider_origin = entity_origin.GetComponent(ColliderComponent).?;
            const collider_target = entity_target.GetComponent(ColliderComponent).?;

            var contact: ?Contact = blk: {
                if (collider_origin.mColliderShape == .Sphere and collider_target.mColliderShape == .Sphere) {
                    break :blk Collisions.SphereSphere(
                        collider_origin.AsSphere(),
                        entity_origin.GetComponent(EntityTransformComponent).?.GetWorldPosition(),
                        collider_target.AsSphere(),
                        entity_target.GetComponent(EntityTransformComponent).?.GetWorldPosition(),
                    );
                } else if (collider_origin.mColliderShape == .Box and collider_target.mColliderShape == .Box) {
                    break :blk Collisions.BoxBox(
                        collider_origin.AsBox(),
                        entity_origin.GetComponent(EntityTransformComponent).?.GetWorldPosition(),
                        collider_target.AsBox(),
                        entity_target.GetComponent(EntityTransformComponent).?.GetWorldPosition(),
                    );
                } else {
                    std.log.err("Cannot handle collision type between {s} and {s} yet!\n", .{ @tagName(collider_origin.mColliderShape), @tagName(collider_target.mColliderShape) });
                    break :blk null;
                }
            };

            if (contact) |*the_contact| {
                the_contact.mOrigin = entity_origin;
                the_contact.mTarget = entity_target;

                try self._InternalData.Contacts.append(engine_context.EngineAllocator(), the_contact.*);
            }
        }
    }
}

fn ResolveCollisions(contact: Contact, rb_origin: *RigidBodyComponent, rb_target: *RigidBodyComponent) void {
    const rv = rb_target.mVelocity - rb_origin.mVelocity;

    const vel_along_norm = LinAlg.VecDotVec(rv, contact.mNormal);
    if (vel_along_norm > 0) return; //they are already moving apart

    const e: f32 = 0.0; //coefficient of restitution

    const j = (-(1.0 + e) * vel_along_norm) / (rb_origin.mInvMass + rb_target.mInvMass); //magnitude of the impulse

    const impulse = contact.mNormal * @as(Vec3f32, @splat(j));

    rb_origin.mVelocity -= impulse * @as(Vec3f32, @splat(rb_origin.mInvMass));
    rb_target.mVelocity += impulse * @as(Vec3f32, @splat(rb_target.mInvMass));
}

fn PositionCorrection(contact: Contact, entity_origin: Entity, rb_origin: *RigidBodyComponent, entity_target: Entity, rb_target: *RigidBodyComponent) void {
    const correction_mag = (@max(contact.mPenetration - SLOP, 0.0)) / (rb_origin.mInvMass + rb_target.mInvMass) * PERCENT;
    const correction = @as(Vec3f32, @splat(correction_mag)) * contact.mNormal;

    const transform_origin = entity_origin.GetComponent(EntityTransformComponent).?;
    const transform_target = entity_target.GetComponent(EntityTransformComponent).?;

    transform_origin.Translation -= correction * @as(Vec3f32, @splat(rb_origin.mInvMass));
    transform_target.Translation += correction * @as(Vec3f32, @splat(rb_target.mInvMass));
}

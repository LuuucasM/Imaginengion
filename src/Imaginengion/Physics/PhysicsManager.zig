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

const PhysicsManager = @This();

mPhysicsDT: f32 = 1 / 60,
mAccumulator: f32 = 0,

pub fn OnUpdate(self: *PhysicsManager, engine_context: *EngineContext, scene_manager: *SceneManager, dt: f32) !void {
    self.mAccumulator += dt;

    while (self.mAccumulator >= self.mPhysicsDT) : (self.mAccumulator -= self.mPhysicsDT) {
        const rigid_body_arr = try scene_manager.GetEntityGroup(engine_context.FrameAllocator(), .{ .Component = RigidBodyComponent });

        for (rigid_body_arr.items) |entity_id| {
            const entity = scene_manager.GetEntity(entity_id);
            const entity_rb = entity.GetComponent(RigidBodyComponent).?;
            ApplyForces(entity, scene_manager, entity_rb);
            IntegrateVelocities(entity_rb, dt);
        }
        DetectCollisions(engine_context, scene_manager);

        //TODO:
        ResolveCollisions();
        IntegratePositions();
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

fn ApplyForces(entity: Entity, scene_manager: *SceneManager, entity_rb: *RigidBodyComponent) !void {
    const entity_scene_comp = entity.GetComponent(EntitySceneComponent).?;
    const scene_layer = scene_manager.GetSceneLayer(entity_scene_comp.SceneID);
    if (scene_layer.GetComponent(ScenePhysicsComponent)) |physics_component| {
        entity_rb.mForce += physics_component.mGravity * entity_rb.mMass;
    } else {
        entity_rb.mForce += 0 * entity_rb.mMass;
    }
}

fn IntegrateVelocities(entity_rb: *RigidBodyComponent, dt: f32) void {
    entity_rb.mVelocity = entity_rb.mForce * entity_rb.mInvMass * dt;
    entity_rb.mForce = std.mem.zeroes(Vec3f32);
}

fn DetectCollisions(engine_context: *EngineContext, scene_manager: *SceneManager) void {
    const colliders_arr = try scene_manager.GetEntityGroup(engine_context.FrameAllocator(), .{ .Component = ColliderComponent });

    for (colliders_arr.items) |colliderid_origin| {
        for (colliders_arr.items) |colliderid_target| {
            const entity_origin = scene_manager.GetEntity(colliderid_origin);
            const entity_target = scene_manager.GetEntity(colliderid_target);

            const collider_origin = entity_origin.GetComponent(ColliderComponent).?;
            const collider_target = entity_target.GetComponent(ColliderComponent).?;

            if (collider_origin.mColliderShape == .Sphere and collider_target.mColliderShape == .Sphere) {
                if (Collisions.SphereSphere(
                    collider_origin.AsSphere(),
                    entity_origin.GetComponent(EntityTransformComponent).?.GetWorldPosition(),
                    collider_target.AsSphere(),
                    entity_target.GetComponent(EntityTransformComponent).?.GetWorldPosition(),
                )) |contact| {
                    //set origin and target entities
                    contact.mOrigin = entity_origin;
                    contact.mTarget = entity_target;

                    //add to some contact buffer
                }
            } else if (collider_origin.mColliderShape == .Box and collider_target.mColliderShape == .Box) {
                if (Collisions.BoxBox(
                    collider_origin.AsBox(),
                    entity_origin.GetComponent(EntityTransformComponent).?.GetWorldPosition(),
                    collider_target.AsBox(),
                    entity_target.GetComponent(EntityTransformComponent).?.GetWorldPosition(),
                )) |contact| {
                    //set origin and target entities
                    contact.mOrigin = entity_origin;
                    contact.mTarget = entity_target;

                    //add to some contact buffer
                }
            } else {
                std.log.err("Cannot handle collision type between {s} and {s} yet!\n", .{ @tagName(collider_origin.mColliderShape), @tagName(collider_target.mColliderShape) });
            }
        }
    }
}

fn ResolveCollisions() void {}

fn IntegratePositions() void {}

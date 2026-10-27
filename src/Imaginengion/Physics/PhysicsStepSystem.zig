//! The substeps of one fixed physics step, and the forces let go of after them (see PhysicsManager.Step, which runs it
//! after the step's listeners). They hold lists of body and collider ids, and the contacts between them, across the
//! pre-solve scripts, so adding or removing any of these waits until the step is done: a script deleting a body, or
//! adding a collider, can't leave a dead id or a moved array behind it.
//!
//!     try engine_context.mSystems.RunSystem(PhysicsStepSystem, engine_context, &world.mEManager.mECSManager, .{world});
const std = @import("std");
const BVHRefitSystem = @import("../Core/BVHRefitSystem.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const WorldManager = @import("../Core/WorldManager.zig");
const Tracy = @import("../Core/Tracy.zig");
const BVH = @import("../Core/BVH.zig");
const Systems = @import("../ECS/Systems.zig");
const GroupQuery = @import("../ECS/ECSManager.zig").GroupQuery;
const Entity = @import("../ECSObjects/Entity.zig");
const SManager = @import("../ECSManagers/SManager.zig");
const PhysicsManager = @import("PhysicsManager.zig");
const CollisionManager = @import("CollisionManager.zig");
const TransformSystem = @import("TransformSystem.zig");

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const RigidBodyComponent = EntityComponents.RigidBodyComponent;
const DynamicBodyTag = EntityComponents.DynamicBodyTag;
const KinematicBodyTag = EntityComponents.KinematicBodyTag;
const ConstantForceComponent = EntityComponents.ConstantForceComponent;
const ColliderComponent = EntityComponents.ColliderComponent;
const EntitySceneComponent = EntityComponents.EntitySceneComponent;
const TransformComponent = EntityComponents.TransformComponent;
const ScenePhysicsComponent = @import("../ECSComponents/SComponents.zig").PhysicsComponent;

const Vec3 = @import("../Math/MathTypes.zig").Vec3;

pub const Name = "PhysicsStep";
pub const Reads = &.{
    ColliderComponent,
    ConstantForceComponent,
    //gravity: each body's scene, and that scene's physics settings
    EntitySceneComponent,
    Systems.In(SManager.ECSManagerT, ScenePhysicsComponent),
};
pub const Writes = &.{ RigidBodyComponent, TransformComponent };

const RigidBodyQuery = GroupQuery{ .Component = RigidBodyComponent };
//moved by forces, gravity and their velocity
const DynamicBodiesQuery = GroupQuery{ .And = &.{ RigidBodyQuery, GroupQuery{ .Component = DynamicBodyTag } } };
//moved by their velocity alone. static bodies have no query: they are never integrated
const KinematicBodiesQuery = GroupQuery{ .And = &.{ RigidBodyQuery, GroupQuery{ .Component = KinematicBodyTag } } };
//the dynamic bodies with a push that stays on them, the only ones a constant force can move
const ConstantForceBodiesQuery = GroupQuery{ .And = &.{ DynamicBodiesQuery, GroupQuery{ .Component = ConstantForceComponent } } };

const SUB_STEP_DT = PhysicsManager.SUB_STEP_DT;

pub fn Run(engine_context: *EngineContext, world_manager: *WorldManager) !void {
    const physics = &world_manager.mPhysicsManager;

    //fetched after the step's listeners, which may have added bodies or changed their types, and once for every substep
    //below: this system's lock keeps the substeps from adding or removing a body or a collider, so the lists can't go stale
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
        const rotation = entity.GetComponent(TransformComponent).?.GetWorldRotation();
        const force = constant_force.mForce.AddVec(constant_force.mLocalForce.QuatRotate(rotation));
        entity.GetComponentMut(RigidBodyComponent).?.ApplyForce(force);
    }

    //contacts are found before anything moves, from where the bodies are and how fast they are going, so
    //the solver can stop a body at a surface before the move that would have carried it through
    for (0..PhysicsManager.SUB_STEPS) |_| {
        {
            //one zone for the whole pass: per-body zones would cost more than the few multiply-adds they time
            const integrate_zone = Tracy.ZoneInit("PhysicsStepSystem::IntegrateVelocities", @src());
            defer integrate_zone.Deinit();
            integrate_zone.Value(dynamic_bodies.items.len);

            //only dynamic bodies: code sets a kinematic body's velocity and nothing else changes it, no
            //gravity and no force
            for (dynamic_bodies.items) |entity_id| {
                const entity = world_manager.GetEntity(entity_id);
                const entity_rb = entity.GetComponentMut(RigidBodyComponent).?;
                IntegrateVelocities(entity_rb, GravityOf(entity, entity_rb), SUB_STEP_DT);
            }
        }

        //where the bodies start the substep, which is what the contacts are measured from
        try engine_context.mSystems.RunSystem(TransformSystem, engine_context, &world_manager.mEManager.mECSManager, .{world_manager});
        //and the world's tree with them: only the colliders, all the broad pass walks. Also takes in whatever moved
        //since the tree was built, before physics, so no refit is needed ahead of the step
        try engine_context.mSystems.RunSystem(BVHRefitSystem, engine_context, &world_manager.mEManager.mECSManager, .{ world_manager, BVH.Mask.PHYSICS });

        try physics._CollisionManager.BroadPass(engine_context, world_manager, collider_groups);
        physics._CollisionManager.NarrowPass(SUB_STEP_DT);
        try physics._CollisionManager.PreSolverPass(engine_context, &physics.mEventManager);
        physics._CollisionManager.SolveVelocities(SUB_STEP_DT);
        physics._CollisionManager.SweepTriggers(SUB_STEP_DT);

        {
            const integrate_zone = Tracy.ZoneInit("PhysicsStepSystem::IntegratePositions", @src());
            defer integrate_zone.Deinit();
            integrate_zone.Value(moving_body_count);

            for (dynamic_bodies.items) |entity_id| {
                const entity = world_manager.GetEntity(entity_id);
                try IntegratePositions(engine_context, entity, entity.GetComponentMut(RigidBodyComponent).?, SUB_STEP_DT);
            }
            for (kinematic_bodies.items) |entity_id| {
                const entity = world_manager.GetEntity(entity_id);
                try IntegratePositions(engine_context, entity, entity.GetComponentMut(RigidBodyComponent).?, SUB_STEP_DT);
            }
        }

        try physics._CollisionManager.CorrectPositions(world_manager, engine_context);
        try physics._CollisionManager.UpdateTouching(engine_context, &physics.mEventManager);
        try physics._CollisionManager.PostsolverPass(engine_context);
        physics._CollisionManager.EndPass(engine_context);
    }

    //a force pushes for one step. Whatever applied it applies it again next step for as long as it should keep
    //pushing. A kinematic body's are let go of too: it is never pushed by them, but they shouldn't pile up
    for (dynamic_bodies.items) |entity_id| {
        world_manager.GetEntity(entity_id).GetComponentMut(RigidBodyComponent).?._Force = std.mem.zeroes(Vec3(f32));
    }
    for (kinematic_bodies.items) |entity_id| {
        world_manager.GetEntity(entity_id).GetComponentMut(RigidBodyComponent).?._Force = std.mem.zeroes(Vec3(f32));
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
    const transform = entity.GetComponent(TransformComponent).?;
    var translation = transform.GetTranslation();
    translation.AddEqVec(entity_rb._Velocity.MulScalar(dt));
    try entity.SetTranslation(engine_context, translation);
}

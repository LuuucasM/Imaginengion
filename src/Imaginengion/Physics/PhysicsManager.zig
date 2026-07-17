const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const SceneManager = @import("../Scene/SceneManager.zig");

const Entity = @import("../GameObjects/Entity.zig");

const EntityComponents = @import("../GameObjects/Components.zig");
const RigidBodyComponent = EntityComponents.RigidBodyComponent;
const ColliderComponent = EntityComponents.ColliderComponent;
const EntitySceneComponent = EntityComponents.EntitySceneComponent;
const EntityTransformComponent = EntityComponents.TransformComponent;
const ChildComponent = @import("../ECS/Components.zig").ChildComponent(Entity.Type);
const ParentComponent = @import("../ECS/Components.zig").ParentComponent(Entity.Type);
const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;
const SceneComponents = @import("../Scene/SceneComponents.zig");
const ScenePhysicsComponent = SceneComponents.PhysicsComponent;
const CollisionManager = @import("CollisionManager.zig");

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

const SUB_STEPS: u32 = 4;
const SUB_STEP_DT: f32 = PHYSICS_DT / @as(f32, @floatFromInt(SUB_STEPS));

_CollisionManager: CollisionManager = .empty,
_InternalData: InternalData = .empty,

pub fn Init(self: *PhysicsManager, engine_allocator: std.mem.Allocator) !void {
    try self._CollisionManager.Init(engine_allocator);
}

pub fn Deinit(self: *PhysicsManager, engine_allocator: std.mem.Allocator) void {
    const zone = Tracy.ZoneInit("PhysicsManager::Deinit", @src());
    defer zone.Deinit();
    self._CollisionManager.Deinit(engine_allocator);
}

pub fn OnUpdate(self: *PhysicsManager, engine_context: *EngineContext, comptime world_type: EngineContext.WorldType) !void {
    const zone = Tracy.ZoneInit("PhysicsManager::OnUpdate", @src());
    defer zone.Deinit();
    var scene_manager = switch (world_type) {
        .Game => engine_context.mGameWorld,
        .Editor => engine_context.mEditorWorld,
        .Simulate => engine_context.mSimulateWorld,
    };
    self._InternalData.Accumulator += engine_context.mDT;

    const rigid_body_arr = try scene_manager.GetEntityGroup(engine_context.FrameAllocator(), .{ .Component = RigidBodyComponent });

    while (self._InternalData.Accumulator >= PHYSICS_DT) : (self._InternalData.Accumulator -= PHYSICS_DT) {
        for (0..SUB_STEPS) |_| {
            for (rigid_body_arr.items) |entity_id| {
                const entity = scene_manager.GetEntity(entity_id);
                const entity_rb = entity.GetComponent(RigidBodyComponent).?;

                ApplyForces(entity, entity_rb);

                IntegrateVelocities(entity_rb, SUB_STEP_DT);
                IntegratePositions(entity, entity_rb, SUB_STEP_DT);
            }

            try UpdateWorldTransforms(world_type, engine_context);

            self._CollisionManager.DetectCollisions(engine_context, scene_manager);
            self._CollisionManager.ResolveCollisions();

            self._CollisionManager.Reset(engine_context.EngineAllocator());
        }
    }
}

pub fn UpdateWorldTransforms(comptime world_type: EngineContext.WorldType, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("PhysicsManager::UpdateWorldTransform", @src());
    defer zone.Deinit();

    var scene_manager = switch (world_type) {
        .Game => &engine_context.mGameWorld,
        .Editor => &engine_context.mEditorWorld,
        .Simulate => &engine_context.mSimulateWorld,
    };

    const EntityTransformQuery = GroupQuery{ .Component = EntityTransformComponent };
    const ChildQuery = GroupQuery{ .Component = ChildComponent };

    const transforms_arr = try scene_manager.GetEntityGroup(
        engine_context.FrameAllocator(),
        .{ .Not = .{ .mFirst = &EntityTransformQuery, .mSecond = &ChildQuery } },
    );

    for (transforms_arr.items) |entity_id| {
        const entity = scene_manager.GetEntity(entity_id);
        const transform = entity.GetComponent(EntityTransformComponent).?;

        transform.SetWorldPosition(transform.Translation);
        transform.SetWorldRotation(transform.Rotation);
        transform.SetWorldScale(transform.Scale);

        if (entity.GetComponent(ParentComponent)) |parent_component| {
            if (parent_component.mFirstEntity != Entity.NullEntity) {
                CalculateChildren(entity, transform.GetWorldPosition(), transform.GetWorldRotation(), transform.GetWorldScale());
            }
        }
    }
}

fn CalculateChildren(parent_entity: Entity, position_acc: Vec3(f32), rotation_acc: Quat(f32), scale_acc: Vec3(f32)) void {
    const parent_component = parent_entity.GetComponent(ParentComponent).?;

    var curr_id = parent_component.mFirstEntity;

    while (true) : (if (curr_id == parent_component.mFirstEntity) break) {
        const child_entity = Entity{ .mEntityID = curr_id, .mSceneManager = parent_entity.mSceneManager };

        CalculateChildTransform(child_entity, position_acc, rotation_acc, scale_acc);

        const child_component = child_entity.GetComponent(ChildComponent).?;
        curr_id = child_component.mNext;
    }
}

fn CalculateChildTransform(child_entity: Entity, position_acc: Vec3(f32), rotation_acc: Quat(f32), scale_acc: Vec3(f32)) void {
    const transform = child_entity.GetComponent(EntityTransformComponent).?;

    transform.SetWorldPosition(transform.Translation.AddVec(position_acc));
    transform.SetWorldRotation(rotation_acc.MulQuat(transform.Rotation));
    transform.SetWorldScale(transform.Scale.AddVec(scale_acc));

    if (child_entity.GetComponent(ParentComponent)) |parent_component| {
        _ = parent_component;
        CalculateChildren(child_entity, transform.GetWorldPosition(), transform.GetWorldRotation(), transform.GetWorldScale());
    }
}

fn ApplyForces(entity: Entity, entity_rb: *RigidBodyComponent) void {
    const zone = Tracy.ZoneInit("PhysicsManager::ApplyForces", @src());
    defer zone.Deinit();
    const entity_scene_comp = entity.GetComponent(EntitySceneComponent).?;
    const scene_layer = entity_scene_comp.mScene;

    if (scene_layer.GetComponent(ScenePhysicsComponent)) |physics_component| {
        if (entity_rb._InvMass != 0) {
            entity_rb.ApplyForce(physics_component.mGravity.MulScalar(entity_rb.mMass));
        }
    }
}

fn IntegrateVelocities(entity_rb: *RigidBodyComponent, dt: f32) void {
    const zone = Tracy.ZoneInit("PhysicsManager::IntegrateVelocities", @src());
    defer zone.Deinit();
    entity_rb.AddVelocity(entity_rb._Force.MulScalar(entity_rb._InvMass * dt));
    entity_rb._Force = std.mem.zeroes(Vec3(f32));
}

fn IntegratePositions(entity: Entity, entity_rb: *RigidBodyComponent, dt: f32) void {
    const zone = Tracy.ZoneInit("PhysicsManager::IntegratePositions", @src());
    defer zone.Deinit();
    const transform = entity.GetComponent(EntityTransformComponent).?;
    transform.Translation.AddEqVec(entity_rb._Velocity.MulScalar(dt));
}

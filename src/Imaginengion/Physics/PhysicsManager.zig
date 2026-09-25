const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const WorldManager = @import("../Core/WorldManager.zig");

const Entity = @import("../ECSObjects/Entity.zig");

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const RigidBodyComponent = EntityComponents.RigidBodyComponent;
const ColliderComponent = EntityComponents.ColliderComponent;
const EntitySceneComponent = EntityComponents.EntitySceneComponent;
const EntityTransformComponent = EntityComponents.TransformComponent;
const ChildComponent = @import("../ECS/Components.zig").ChildComponent(Entity.Type);
const ParentComponent = @import("../ECS/Components.zig").ParentComponent(Entity.Type);
const TransformDirtyTag = EntityComponents.TransformDirtyTag;
const SceneComponents = @import("../ECSComponents/SComponents.zig");
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

const SUB_STEPS: u32 = 2;

//the transform walk adds translations and multiplies rotations and scales,
//so this is what a root of the hierarchy accumulates from
const IDENTITY_POSITION: Vec3(f32) = .{ .x = 0.0, .y = 0.0, .z = 0.0 };
const IDENTITY_ROTATION: Quat(f32) = .{ .w = 1.0, .x = 0.0, .y = 0.0, .z = 0.0 };
const IDENTITY_SCALE: Vec3(f32) = .{ .x = 1.0, .y = 1.0, .z = 1.0 };
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

    var world_manager = switch (world_type) {
        .Game => &engine_context.mGameWorld,
        .Editor => &engine_context.mEditorWorld,
        .Simulate => &engine_context.mSimulateWorld,
    };
    self._InternalData.Accumulator += engine_context.mDT;

    //fixed steps run this frame: normally 0 or 1, and climbing means physics is falling behind real time
    var steps: usize = 0;
    defer Tracy.Plot("Physics/Steps Per Frame", .{ .color = 0xF44336 }, steps);

    //the same condition the step loop below runs on, so a frame that will not step skips the group
    //queries too instead of building lists nothing reads
    if (self._InternalData.Accumulator < PHYSICS_DT) return;

    const rigid_body_arr = try world_manager.GetEntityGroup(engine_context.FrameAllocator(), .{ .Component = RigidBodyComponent });
    Tracy.Plot("Physics/Rigid Bodies", .{ .color = 0xE91E63 }, rigid_body_arr.items.len);

    //fetched once for every substep of every step below, the same as rigid_body_arr. Nothing in here
    //adds or removes a collider or a body tag, so the lists cannot go stale between substeps
    const dynamic_colliders = try world_manager.GetEntityGroup(engine_context.FrameAllocator(), CollisionManager.DynamicCollidersQuery);
    const other_colliders = try world_manager.GetEntityGroup(engine_context.FrameAllocator(), CollisionManager.OtherCollidersQuery);

    while (self._InternalData.Accumulator >= PHYSICS_DT) : (self._InternalData.Accumulator -= PHYSICS_DT) {
        steps += 1;
        for (0..SUB_STEPS) |_| {
            {
                //one zone for the whole pass: per-body zones would cost more than the few multiply-adds they time
                const integrate_zone = Tracy.ZoneInit("PhysicsManager::Integrate", @src());
                defer integrate_zone.Deinit();
                integrate_zone.Value(rigid_body_arr.items.len);

                for (rigid_body_arr.items) |entity_id| {
                    const entity = world_manager.GetEntity(entity_id);
                    const entity_rb = entity.GetComponent(RigidBodyComponent).?;

                    ApplyForces(entity, entity_rb);

                    IntegrateVelocities(entity_rb, SUB_STEP_DT);
                    try IntegratePositions(engine_context, entity, entity_rb, SUB_STEP_DT);
                }
            }

            try UpdateWorldTransforms(world_type, engine_context);

            try self._CollisionManager.BroadPass(engine_context, world_manager, dynamic_colliders.items, other_colliders.items);
            try self._CollisionManager.NarrowPass(engine_context);
            try self._CollisionManager.PreSolverPass(engine_context);
            try self._CollisionManager.SolverPass(world_type, engine_context);
            try self._CollisionManager.PostsolverPass(engine_context);
            self._CollisionManager.EndPass(engine_context);
        }
    }
}

pub fn UpdateWorldTransforms(comptime world_type: EngineContext.WorldType, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("PhysicsManager::UpdateWorldTransforms", @src());
    defer zone.Deinit();

    var world_manager = switch (world_type) {
        .Game => &engine_context.mGameWorld,
        .Editor => &engine_context.mEditorWorld,
        .Simulate => &engine_context.mSimulateWorld,
    };

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
        //CalculateEntityTransform assigns world = local + accumulator instead of accumulating into
        //itself. That is also why a parent and child both being dirty is merely redundant work
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
        transform.SetWorldPosition(transform.GetTranslation().AddVec(position_acc));
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

fn ApplyForces(entity: Entity, entity_rb: *RigidBodyComponent) void {
    const entity_scene_comp = entity.GetComponent(EntitySceneComponent).?;
    const scene_layer = entity_scene_comp.mScene;

    if (scene_layer.GetComponent(ScenePhysicsComponent)) |physics_component| {
        if (entity_rb._InvMass != 0) {
            entity_rb.ApplyForce(physics_component.mGravity.MulScalar(entity_rb.mMass));
        }
    }
}

fn IntegrateVelocities(entity_rb: *RigidBodyComponent, dt: f32) void {
    entity_rb.AddVelocity(entity_rb._Force.MulScalar(entity_rb._InvMass * dt));
    entity_rb._Force = std.mem.zeroes(Vec3(f32));
}

fn IntegratePositions(engine_context: *EngineContext, entity: Entity, entity_rb: *RigidBodyComponent, dt: f32) !void {
    const transform = entity.GetComponent(EntityTransformComponent).?;
    var translation = transform.GetTranslation();
    translation.AddEqVec(entity_rb._Velocity.MulScalar(dt));
    try entity.SetTranslation(engine_context, translation);
}

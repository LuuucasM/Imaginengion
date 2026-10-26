//! The world transform pass: brings every moved transform's world values up to date, and those of everything under
//! it. Run before the world's trees are built, before drawing, and inside the physics step after anything moves:
//!
//!     try engine_context.mSystems.RunSystem(TransformSystem, engine_context, &world.mEManager.mECSManager, .{world});
const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const WorldManager = @import("../Core/WorldManager.zig");
const Entity = @import("../ECSObjects/Entity.zig");

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const TransformComponent = EntityComponents.TransformComponent;
const TransformDirtyTag = EntityComponents.TransformDirtyTag;
const ChildComponent = @import("../ECS/Components.zig").ChildComponent(Entity.Type);
const ParentComponent = @import("../ECS/Components.zig").ParentComponent(Entity.Type);

const MathTypes = @import("../Math/MathTypes.zig");
const Vec3 = MathTypes.Vec3;
const Quat = MathTypes.Quat;

pub const Name = "WorldTransforms";
pub const Reads = &.{};
pub const Writes = &.{TransformComponent};

//the transform walk adds translations and multiplies rotations and scales,
//so this is what a root of the hierarchy accumulates from
const IDENTITY_POSITION: Vec3(f32) = .{ .x = 0.0, .y = 0.0, .z = 0.0 };
const IDENTITY_ROTATION: Quat(f32) = .{ .w = 1.0, .x = 0.0, .y = 0.0, .z = 0.0 };
const IDENTITY_SCALE: Vec3(f32) = .{ .x = 1.0, .y = 1.0, .z = 1.0 };

pub fn Run(engine_context: *EngineContext, world_manager: *WorldManager) !void {
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
        //CalculateEntityTransform assigns world from local and the accumulator instead of accumulating
        //into itself. That is also why a parent and child both being dirty is merely redundant work
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

        if (parent_entity.GetComponent(TransformComponent)) |parent_transform| {
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

    if (entity.GetComponentMut(TransformComponent)) |transform| {
        //the local position is an offset in the parent's space: it stretches with the parent's scale
        //and turns with its rotation before it is added on, so a child orbits a turning parent and
        //moves out with a growing one instead of staying put
        transform.SetWorldPosition(position_acc.AddVec(transform.GetTranslation().MulVec(scale_acc).QuatRotate(rotation_acc)));
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

//! What a physics step has to report. The events are queued on the PhysicsManager of the world that was
//! stepped (see Physics/CollisionManager.zig, which sends them), and the entities in them are that world's.
const Entity = @import("../ECSObjects/Entity.zig");
const Vec3 = @import("../Math/MathTypes.zig").Vec3;

pub const EventCategories = enum {
    /// queued during a physics step, processed once the step is over and before game logic. Never inside
    /// the step: what reacts to these is free to move or delete things, which the step's contact lists
    /// could not survive
    PostPhysics,
};

pub const EventT = union(enum) {
    Default: DefaultEvent,
    CollisionBegin: CollisionBeginEvent,
};

pub const DefaultEvent = struct {};

/// Two colliders that were apart on the last physics substep are overlapping on this one.
/// Sent once per pair: nothing more is sent while they stay in contact
pub const CollisionBeginEvent = struct {
    mOrigin: Entity,
    mTarget: Entity,
    //points from mOrigin to mTarget
    mNormal: Vec3(f32),
    //one of the two is a trigger, so they passed through each other instead of being pushed apart
    mIsTrigger: bool,
};

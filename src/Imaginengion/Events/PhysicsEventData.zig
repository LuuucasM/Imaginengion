//! What a physics step has to report. The events are queued on the PhysicsManager of the world that was
//! stepped (see Physics/CollisionManager.zig, which sends them), and the entities in them are that world's.
//! StepBegin and PreSolve are the exceptions: dispatched synchronously, at the start of each step and before each
//! substep's solver, and never queued.
const Entity = @import("../ECSObjects/Entity.zig");
const WorldManager = @import("../Core/WorldManager.zig");
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
    CollisionEnd: CollisionEndEvent,
    StepBegin: StepBeginEvent,
    PreSolve: PreSolveEvent,
};

pub const DefaultEvent = struct {};

/// A fixed physics step is about to start on mWorld. Dispatched synchronously (EventManager.Dispatch), never
/// queued: what listens runs right then, before the step and once per step, at the physics' own fixed rate
/// rather than once a frame. The program runs the world's OnPhysicsUpdate scripts on it. A force applied while
/// handling it pushes for the whole step
pub const StepBeginEvent = struct {
    mWorld: *WorldManager,
    //the length of the step in seconds, the same every step
    mDT: f32,
};

/// The solver is about to act on a solid contact, one of whose colliders asked for this (ColliderComponent
/// mPreSolveEvents). Dispatched synchronously like StepBegin, never queued, once per such contact every substep, and
/// from the middle of the step: the contact lists are live, so whatever listens may only read the world and decide
/// mEnabled. It must not create, delete or move anything. The program runs the two game objects' OnPreSolve scripts
/// on it. Trigger contacts are never handed over, nothing solves them
pub const PreSolveEvent = struct {
    //the game objects in contact (Entity.GetMainObject of each collider), which their scripts run for
    mOrigin: Entity,
    mTarget: Entity,
    //the colliders in contact
    mOriginCollider: Entity,
    mTargetCollider: Entity,
    //points from mOrigin to mTarget
    mNormal: Vec3(f32),
    //the gap between them along mNormal, negative while they overlap
    mSeparation: f32,
    //the answer: true when the event arrives, set to false to have the solver leave this contact be on this substep.
    //Only valid during the dispatch, the same as the event
    mEnabled: *bool,
};

/// Two colliders that were apart on the last physics substep touch on this one: the solver stopped them at each
/// other's surface, or they overlap. Sent once per pair of colliders, nothing more while they stay in contact, so a
/// game object with several colliders can begin touching the same thing once for each of its colliders that does
pub const CollisionBeginEvent = struct {
    //the game objects that touched (Entity.GetMainObject of each collider), which their scripts run for
    mOrigin: Entity,
    mTarget: Entity,
    //the colliders that touched, each one its game object or a convenience child of it
    mOriginCollider: Entity,
    mTargetCollider: Entity,
    //points from mOrigin to mTarget
    mNormal: Vec3(f32),
    //one of the two is a trigger, so they passed through each other instead of being pushed apart
    mIsTrigger: bool,
};

/// Two colliders that touched on the last physics substep no longer do on this one, the counterpart of a
/// CollisionBeginEvent: every pair that began touching ends exactly once. A pair ends when the two come apart, but
/// also when it stops being a pair at all: a collider whose filter now ignores the other, a collider taken off, or
/// an entity deleted. So any of the four entities may no longer exist by the time this is handled. No normal: the
/// two are apart, or one of them is gone
pub const CollisionEndEvent = struct {
    //the game objects that were touching (Entity.GetMainObject of each collider), as they were when they last touched
    mOrigin: Entity,
    mTarget: Entity,
    //the colliders that were touching
    mOriginCollider: Entity,
    mTargetCollider: Entity,
    //one of the two was a trigger
    mIsTrigger: bool,
};

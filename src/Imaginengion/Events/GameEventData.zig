const Entity = @import("../ECSObjects/Entity.zig");
const EEntityComponents = @import("../ECSComponents/EComponents.zig").EComponents;

const SceneLayer = @import("../ECSObjects/Scene.zig");
const ESceneComponents = @import("../ECSComponents/SComponents.zig").EComponents;

const Player = @import("../ECSObjects/Player.zig");
const EPlayerComponents = @import("../ECSComponents/PComponents.zig").EComponents;

const GameContext = @import("../ECSObjects/GameContext.zig");
const EGameContextComponents = @import("../ECSComponents/GCComponents.zig").EComponents;

const Vec3 = @import("../Math/MathTypes.zig").Vec3;

pub const EventCategories = enum {
    EndOfFrame,
    //queued by the physics step, for whatever runs right after it
    PostPhysics,
};

pub const EventT = union(enum) {
    Default: DefaultEvent,
    CollisionBeginEvent: CollisionBeginEvent,
    DestroyEntityEvent: DestroyEntityEvent,
    DestroySceneEvent: DestroySceneEvent,
    DestroyPlayerEvent: DestroyPlayerEvent,
    DestroyGameContextEvent: DestroyGameContextEvent,
    RmEntityCompEvent: RmEntityCompEvent,
    RmSceneCompEvent: RmSceneCompEvent,
    RmPlayerCompEvent: RmPlayerCompEvent,
    RmGameContextCompEvent: RmGameContextCompEvent,
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

pub const DestroyEntityEvent = struct {
    mEntity: Entity,
};

pub const DestroySceneEvent = struct {
    mScene: SceneLayer,
};

pub const DestroyPlayerEvent = struct {
    mPlayer: Player,
};

pub const DestroyGameContextEvent = struct {
    mGameContext: GameContext,
};

pub const RmEntityCompEvent = struct {
    mEntity: Entity,
    mComponentType: EEntityComponents,
};

pub const RmSceneCompEvent = struct {
    mScene: SceneLayer,
    mComponentType: ESceneComponents,
};

pub const RmPlayerCompEvent = struct {
    mPlayer: Player,
    mComponentType: EPlayerComponents,
};

pub const RmGameContextCompEvent = struct {
    mGameContext: GameContext,
    mComponentType: EGameContextComponents,
};

const Entity = @import("../ECSObjects/Entity.zig");
const EEntityComponents = @import("../ECSComponents/EComponents.zig").EComponents;

const SceneLayer = @import("../ECSObjects/Scene.zig");
const ESceneComponents = @import("../ECSComponents/SComponents.zig").EComponents;

const Player = @import("../ECSObjects/Player.zig");
const EPlayerComponents = @import("../ECSComponents/PComponents.zig").EComponents;

const GameContext = @import("../ECSObjects/GameContext.zig");
const EGameContextComponents = @import("../ECSComponents/GCComponents.zig").EComponents;

pub const EventCategories = enum {
    EndOfFrame,
};

pub const Event = union(enum) {
    Default: DefaultEvent,
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

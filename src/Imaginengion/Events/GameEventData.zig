const Entity = @import("../GameObjects/Entity.zig");
const EEntityComponents = @import("../GameObjects/Components.zig").EComponents;

const SceneLayer = @import("../Scene/SceneLayer.zig");
const ESceneComponents = @import("../Scene/SceneComponents.zig").EComponents;

const Player = @import("../Players/Player.zig");
const EPlayerComponents = @import("../Players/Components.zig").EComponents;

const GameContext = @import("../GameModes/GameMode.zig");
const EGameContextComponents = @import("../GameModes/Components.zig").EComponents;

pub const EventCategories = enum {
    FrameEnd,
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

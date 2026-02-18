const Entity = @import("../GameObjects/Entity.zig");
const EEntityComponents = @import("../GameObjects/Components.zig").EComponents;

const SceneLayer = @import("SceneLayer.zig");
const ESceneComponents = @import("SceneComponents.zig").EComponents;

pub const EventCategories = enum {
    FrameEnd,
};

pub const Event = union(enum) {
    Default: DefaultEvent,
    DestroyEntityEvent: DestroyEntityEvent,
    DestroySceneEvent: DestroySceneEvent,
    RmEntityCompEvent: RmEntityCompEvent,
    RmSceneCompEvent: RmSceneCompEvent,
};

pub const DefaultEvent = struct {};

pub const DestroyEntityEvent = struct {
    mEntity: Entity,
};

pub const DestroySceneEvent = struct {
    mScene: SceneLayer,
};

pub const RmEntityCompEvent = struct {
    mEntity: Entity,
    mComponentType: EEntityComponents,
};

pub const RmSceneCompEvent = struct {
    mScene: SceneLayer,
    mComponentType: ESceneComponents,
};

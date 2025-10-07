const Entity = @import("../GameObjects/Entity.zig");
const EEntityComponents = @import("../GameObjects/Components.zig").EComponents;
const SceneLayer = @import("../Scene/SceneLayer.zig");
const ESceneComponents = @import("../Scene/SceneComponents.zig").EComponents;

pub const GameEventCategory = enum(u8) {
    EC_Default,
    EC_EndOfFrame,
};

pub const GameEvent = union(enum) {
    ET_Default: DefaultEvent,
    ET_DestroyEntityEvent: DestroyEntityEvent,
    ET_DestroySceneEvent: DestroySceneEvent,
    ET_RmEntityCompEvent: RmEntityCompEvent,
    ET_RmSceneCompEvent: RmSceneCompEvent,

    pub fn GetEventCategory(self: GameEvent) GameEventCategory {
        switch (self) {
            inline else => |event| return event.GetEventCategory(),
        }
    }
};

pub const DefaultEvent = struct {
    pub fn GetEventCategory(self: DefaultEvent) GameEventCategory {
        _ = self;
        return .EC_Default;
    }
};

pub const DestroyEntityEvent = struct {
    mEntity: Entity,
    pub fn GetEventCategory(self: DestroyEntityEvent) GameEventCategory {
        _ = self;
        return .EC_EndOfFrame;
    }
};

pub const DestroySceneEvent = struct {
    mSceneID: SceneLayer.Type,
    pub fn GetEventCategory(self: DestroySceneEvent) GameEventCategory {
        _ = self;
        return .EC_EndOfFrame;
    }
};

pub const RmEntityCompEvent = struct {
    mEntityID: Entity.Type,
    mComponentType: EEntityComponents,
    pub fn GetEventCategory(self: RmEntityCompEvent) GameEventCategory {
        _ = self;
        return .EC_EndOfFrame;
    }
};

pub const RmSceneCompEvent = struct {
    mSceneID: SceneLayer.Type,
    mComponentType: ESceneComponents,
    pub fn GetEventCategory(self: RmSceneCompEvent) GameEventCategory {
        _ = self;
        return .EC_EndOfFrame;
    }
};

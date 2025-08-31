const Entity = @import("../GameObjects/Entity.zig");
const SceneLayer = @import("../Scene/SceneLayer.zig");

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
    mEntity: Entity.Type,
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
    mEntity: Entity.Type,
    mComponentInd: u32,
    pub fn GetEventCategory(self: RmEntityCompEvent) GameEventCategory {
        _ = self;
        return .EC_EndOfFrame;
    }
};

pub const RmSceneCompEvent = struct {
    mScene: SceneLayer.Type,
    mComponentInd: u32,
    pub fn GetEventCategory(self: RmSceneCompEvent) GameEventCategory {
        _ = self;
        return .EC_EndOfFrame;
    }
};

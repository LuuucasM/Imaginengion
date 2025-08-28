const Entity = @import("../GameObjects/Entity.zig");
const SceneLayer = @import("../Scene/SceneLayer.zig");

pub const GameEventCategory = enum(u8) {
    EC_Default,
    EC_EndOfFrame,
};

pub const GameEvent = union(enum) {
    ET_DefaultEvent: DefaultEvent,
    ET_DestroyEntityEvent: DestroyEntityEvent,
    ET_DestroySceneEvent: DestroySceneEvent,
    ET_RemoveScCompEvent: RemoveScCompEvent,

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

pub const RemoveScCompEvent = struct {
    mScene: SceneLayer.Type,
    mComponentType: type,
    pub fn GetEventCategory(self: DestroyEntityEvent) GameEventCategory {
        _ = self;
        return .EC_EndOfFrame;
    }
};

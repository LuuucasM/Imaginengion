const Entity = @import("../ECSObjects/Entity.zig");

pub const EventCategories = enum(u8) {
    EndOfFrame,
};

pub const EventT = union(enum) {
    Default: DefaultEvent,
    DestroyEntity: DestroyEntityEvent,

    pub const DefaultEvent = struct {};

    pub const DestroyEntityEvent = struct {
        Entity: Entity,
    };
};

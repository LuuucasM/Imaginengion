const Player = @import("../ECSObjects/Player.zig");

pub const EventCategories = enum(u8) {
    Remove,
};

pub const EventT = union(enum) {
    Default: DefaultEvent,

    pub const DefaultEvent = struct {};

    pub const ToDestroyPlayerEvent = struct {
        PlayerID: Player.Type,
    };
};

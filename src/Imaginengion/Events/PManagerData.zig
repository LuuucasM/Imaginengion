const Player = @import("../ECSObjects/Player.zig");

pub const EventCategories = enum(u8) {
    EndOfFrame,
};

pub const EventT = union(enum) {
    Default: DefaultEvent,
    DestroyPlayer: DestroyPlayerEvent,

    pub const DefaultEvent = struct {};

    pub const DestroyPlayerEvent = struct {
        Player: Player,
    };
};

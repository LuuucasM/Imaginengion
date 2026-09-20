const GameContext = @import("../ECSObjects/GameContext.zig");

pub const EventCategories = enum(u8) {
    EndOfFrame,
};

pub const EventT = union(enum) {
    Default: DefaultEvent,
    DestroyGameContext: DestroyGameContextEvent,

    pub const DefaultEvent = struct {};

    pub const DestroyGameContextEvent = struct {
        GameContext: GameContext,
    };
};

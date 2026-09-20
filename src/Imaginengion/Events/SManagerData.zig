const Scene = @import("../ECSObjects/Scene.zig");

pub const EventCategories = enum(u8) {
    EndOfFrame,
};

pub const EventT = union(enum) {
    Default: DefaultEvent,
    ToDestroyScene: DestroySceneEvent,

    pub const DefaultEvent = struct {};

    pub const DestroySceneEvent = struct {
        Scene: Scene,
    };
};

const Scene = @import("../ECSObjects/Scene.zig");

pub const EventCategories = enum(u8) {
    EndOfFrame,
};

pub const EventT = union(enum) {
    Default: DefaultEvent,
    ToDestroyScene: ToDestroySceneEvent,

    pub const DefaultEvent = struct {};

    pub const ToDestroySceneEvent = struct {
        Scene: Scene,
    };
};

const Scene = @import("../ECSObjects/Scene.zig");

pub const EventCategories = enum(u8) {
    Remove,
};

pub const EventT = union(enum) {
    Default: DefaultEvent,

    pub const DefaultEvent = struct {};

    pub const ToDestroySceneEvent = struct {
        SceneID: Scene,
    };
};

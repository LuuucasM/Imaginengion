pub const EventCategories = enum(u8) {
    Remove,
};

pub const EventT = union(enum) {
    Default: DefaultEvent,

    pub const DefaultEvent = struct {};
};

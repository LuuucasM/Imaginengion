pub const EventCategories = enum(u8) {
    EndOfFrame,
};

pub const EventT = union(enum) {
    Default: DefaultEvent,

    pub const DefaultEvent = struct {};
};

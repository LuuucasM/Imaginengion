pub const EventCategories = enum(u8) {
    Remove,
};

pub fn EventT(entity_t: type) type {
    return union(enum) {
        Default: DefaultEvent,
        ToDestroyAsset: ToDestroyAssetEvent,

        pub const DefaultEvent = struct {};

        pub const ToDestroyAssetEvent = struct {
            mAssetID: entity_t,
        };
    };
}

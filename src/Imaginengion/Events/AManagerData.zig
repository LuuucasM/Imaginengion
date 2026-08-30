pub const EventCategories = enum(u8) {
    Remove,
};

pub fn EventT(entity_t: type) type {
    return union(enum) {
        Default: DefaultEvent,
        DestroyEntity: DestroyEntityEvent,
        RemoveComponent: RemoveComponentEvent,

        pub const DefaultEvent = struct {};

        pub const DestroyEntityEvent = struct {
            mEntityID: entity_t,
        };

        pub const RemoveComponentEvent = struct {
            mEntityID: entity_t,
            mComponentInd: usize,
        };
    };
}

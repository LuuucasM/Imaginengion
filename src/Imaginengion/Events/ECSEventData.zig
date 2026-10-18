pub const EventCategories = enum(u8) {
    EndOfFrame,
};

pub fn EventT(entity_t: type) type {
    return union(enum) {
        Default: DefaultEvent,
        AddComponent: AddComponentEvent,
        DestroyEntity: DestroyEntityEvent,
        RemoveComponent: RemoveComponentEvent,

        pub const DefaultEvent = struct {};

        /// mData points at the component's value. For a queued add that is the staged copy in the ECS's staging
        /// arena, which the ECS has already copied onto the entity by the time listeners see the event, so a
        /// listener reads the component from the entity rather than through mData.
        pub const AddComponentEvent = struct {
            mEntityID: entity_t,
            mComponentInd: usize,
            mData: *anyopaque,
        };

        pub const DestroyEntityEvent = struct {
            mEntityID: entity_t,
        };

        pub const RemoveComponentEvent = struct {
            mEntityID: entity_t,
            mComponentInd: usize,
        };
    };
}

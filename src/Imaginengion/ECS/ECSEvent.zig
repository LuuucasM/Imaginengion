pub const ECSEventCategory = enum(u8) {
    EC_Default,
    EC_DestroyEntities,
    EC_CleanMultiEntities,
};

pub fn ECSEvent(entity_t: type) type {
    return union(enum) {
        const Self = @This();
        ET_Default: DefaultEvent,
        EC_DestroyEntities: DestroyEntityEvent,
        EC_CleanMultiEntities: CleanMultiEntitiesEvent,

        pub fn GetEventCategory(self: Self) ECSEventCategory {
            switch (self) {
                inline else => |event| return event.GetEventCategory(),
            }
        }

        pub const DefaultEvent = struct {
            pub fn GetEventCategory(_: DefaultEvent) ECSEventCategory {
                return .EC_Default;
            }
        };

        pub const DestroyEntityEvent = struct {
            mEntityID: entity_t,
            pub fn GetEventCategory(_: DestroyEntityEvent) ECSEventCategory {
                return .EC_DestroyEntities;
            }
        };

        pub const CleanMultiEntitiesEvent = struct {
            mEntityID: entity_t,
            pub fn GetEventCategory(_: DestroyEntityEvent) ECSEventCategory {
                return .EC_CleanMultiEntities;
            }
        };
    };
}

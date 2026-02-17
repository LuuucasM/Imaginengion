pub const ECSEventCategory = enum(u8) {
    EC_Default,
    EC_Remove,
};

pub fn ECSEvent(entity_t: type) type {
    return union(enum) {
        const Self = @This();
        ET_Default: DefaultEvent,
        ET_DestroyEntity: DestroyEntityEvent,
        ET_RemoveComponent: RemoveComponentEvent,

        pub fn GetEventCategory(self: Self) ECSEventCategory {
            switch (self) {
                .ET_Default => return .EC_Default,
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
                return .EC_Remove;
            }
        };

        pub const RemoveComponentEvent = struct {
            mEntityID: entity_t,
            mComponentInd: usize,
            pub fn GetEventCategory(_: RemoveComponentEvent) ECSEventCategory {
                return .EC_Remove;
            }
        };
    };
}

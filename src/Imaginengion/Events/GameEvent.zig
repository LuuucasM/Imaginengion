pub const GameEventCategory = enum(u8) {
    EC_Default,
    EC_PreRender,
};

pub const GameEvent = union(enum) {
    ET_DefaultEvent: DefaultEvent,
    ET_PrimaryCameraChangeEvent: PrimaryCameraChangeEvent,
    pub fn GetEventCategory(self: GameEvent) GameEventCategory {
        switch (self) {
            inline else => |event| return event.GetEventCategory(),
        }
    }
};

pub const DefaultEvent = struct {
    pub fn GetEventCategory(self: PrimaryCameraChangeEvent) GameEventCategory {
        _ = self;
        return .EC_Default;
    }
};

pub const PrimaryCameraChangeEvent = struct {
    mEntityID: u32,
    pub fn GetEventCategory(self: PrimaryCameraChangeEvent) GameEventCategory {
        _ = self;
        return .EC_PreRender;
    }
};

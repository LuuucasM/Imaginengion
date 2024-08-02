const EventType = @import("EventEnums.zig").EventType;
const EventCategory = @import("EventEnums.zig").EventCategory;

pub const WindowCloseEvent = struct {
    pub fn GetEventCategory(self: WindowCloseEvent) EventCategory {
        _ = self;
        return .EC_Window;
    }
};

pub const WindowResizeEvent = struct {
    pub fn GetEventCategory(self: WindowResizeEvent) EventCategory {
        _ = self;
        return .EC_Window;
    }
    _Width: u32,
    _Height: u32,
};

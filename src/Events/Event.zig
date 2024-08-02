const InputEvents = @import("InputEvents.zig");
const WindowEvents = @import("WindowEvents.zig");
const EventType = @import("EventEnums.zig").EventType;
const EventCategory = @import("EventEnums.zig").EventCategory;

pub const Event = union(EventType) {
    ET_WindowClose: WindowEvents.WindowCloseEvent,
    ET_WindowResize: WindowEvents.WindowResizeEvent,
    ET_KeyPressed: InputEvents.KeyPressedEvent,
    ET_KeyReleased: InputEvents.KeyReleasedEvent,
    ET_MouseButtonPressed: InputEvents.MouseButtonPressedEvent,
    ET_MouseButtonReleased: InputEvents.MouseButtonReleasedEvent,
    ET_MouseMoved: InputEvents.MouseMovedEvent,
    ET_MouseScrolled: InputEvents.MouseScrolledEvent,
    pub fn GetEventCategory(self: Event) EventCategory {
        switch (self) {
            inline else => |event| return event.GetEventCategory(),
        }
    }
};

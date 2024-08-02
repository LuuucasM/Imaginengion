pub const EventType = enum(u16) {
    ET_WindowClose,
    ET_WindowResize,
    ET_KeyPressed,
    ET_KeyReleased,
    ET_MouseButtonPressed,
    ET_MouseButtonReleased,
    ET_MouseMoved,
    ET_MouseScrolled,
};
pub const EventCategory = enum(u8) {
    EC_Input,
    EC_Window,
};

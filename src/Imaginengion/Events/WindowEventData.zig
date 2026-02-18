const InputCodes = @import("../Inputs/InputCodes.zig").InputCodes;

pub const EventCategories = enum {
    InputEvent,
    WindowEvent,
};

pub const Event = union(enum) {
    DefaultEvent: DefaultEvent,
    WindowClose: WindowCloseEvent,
    WindowResize: WindowResizeEvent,
    InputPressed: InputPressedEvent,
    InputReleased: InputReleasedEvent,
    MouseMoved: MouseMovedEvent,
    MouseScrolled: MouseScrolledEvent,
};

pub const DefaultEvent = struct {};

pub const InputPressedEvent = struct {
    _InputCode: InputCodes,
    _Repeat: u16,
};
pub const InputReleasedEvent = struct {
    _InputCode: InputCodes,
};
pub const MouseMovedEvent = struct {
    _MouseX: f32,
    _MouseY: f32,
};

pub const MouseScrolledEvent = struct {
    _XOffset: f32,
    _YOffset: f32,
};

pub const WindowCloseEvent = struct {};

pub const WindowResizeEvent = struct {
    _Width: usize,
    _Height: usize,
};

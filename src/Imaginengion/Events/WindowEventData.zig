const InputEnums = @import("../Inputs/InputEnums.zig");
const ScanCodes = InputEnums.ScanCodes;
const MouseCodes = InputEnums.MouseCodes;
const MouseWheelDir = InputEnums.MouseWheelDir;
const Window = @import("../Windows/Window.zig");

pub const EventCategories = enum {
    InputEvent,
    WindowEvent,
};

pub const EventT = union(enum) {
    DefaultEvent: DefaultEvent,
    WindowClose: WindowCloseEvent,
    WindowResize: WindowResizeEvent,
    KeyboardPressed: KeyboardPressedEvent,
    KeyboardReleased: KeyboardReleasedEvent,
    MousePressed: MousePressedEvent,
    MouseReleased: MouseReleasedEvent,
    MouseClicked: MouseClickedEvent,
    MouseMoved: MouseMovedEvent,
    MouseScrolled: MouseScrolledEvent,
};

pub const DefaultEvent = struct {};

pub const KeyboardPressedEvent = struct {
    _InputCode: ScanCodes,
    _Repeat: u8,
};
pub const KeyboardReleasedEvent = struct {
    _InputCode: ScanCodes,
};
pub const MousePressedEvent = struct {
    _ButtonCode: MouseCodes,
};
pub const MouseReleasedEvent = struct {
    _ButtonCode: MouseCodes,
};
/// Sent after MouseReleased when the button came up where it went down (within the input manager's
/// CLICK_DRAG_THRESHOLD), rather than after a drag.
pub const MouseClickedEvent = struct {
    _ButtonCode: MouseCodes,
    _MouseX: f32, //where it was clicked, in window coordinates
    _MouseY: f32,
    _Clicks: u8, //from SDL: 1 for a single click, 2 for a double click, and so on
};
pub const MouseMovedEvent = struct {
    _MouseX: f32,
    _MouseY: f32,
};

pub const MouseScrolledEvent = struct {
    _XOffset: f32,
    _YOffset: f32,
};

pub const WindowCloseEvent = struct {
    _Window: *anyopaque,
};

pub const WindowResizeEvent = struct {
    _Width: usize,
    _Height: usize,
};

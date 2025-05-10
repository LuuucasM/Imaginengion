const InputCodes = @import("../Inputs/InputCodes.zig").InputCodes;

pub const SystemEventCategory = enum(u2) {
    EC_Default = 0,
    EC_Input = 1,
    EC_Window = 2,
};

pub const SystemEvent = union(enum) {
    ET_DefaultEvent: DefaultEvent,
    ET_WindowClose: WindowCloseEvent,
    ET_WindowResize: WindowResizeEvent,
    ET_InputPressed: InputPressedEvent,
    ET_InputReleased: InputReleasedEvent,
    ET_MouseMoved: MouseMovedEvent,
    ET_MouseScrolled: MouseScrolledEvent,
    pub fn GetEventCategory(self: SystemEvent) SystemEventCategory {
        switch (self) {
            inline else => |event| return event.GetEventCategory(),
        }
    }
};

pub const DefaultEvent = struct {
    pub fn GetEventCategory(self: DefaultEvent) SystemEventCategory {
        _ = self;
        return .EC_Default;
    }
};

pub const InputPressedEvent = struct {
    pub fn GetEventCategory(self: InputPressedEvent) SystemEventCategory {
        _ = self;
        return .EC_Input;
    }

    _InputCode: InputCodes,
    _Repeat: u16,
};
pub const InputReleasedEvent = struct {
    pub fn GetEventCategory(self: InputReleasedEvent) SystemEventCategory {
        _ = self;
        return .EC_Input;
    }

    _InputCode: InputCodes,
};
pub const MouseMovedEvent = struct {
    pub fn GetEventCategory(self: MouseMovedEvent) SystemEventCategory {
        _ = self;
        return .EC_Input;
    }
    _MouseX: f32,
    _MouseY: f32,
};

pub const MouseScrolledEvent = struct {
    pub fn GetEventCategory(self: MouseScrolledEvent) SystemEventCategory {
        _ = self;
        return .EC_Input;
    }
    _XOffset: f32,
    _YOffset: f32,
};

pub const WindowCloseEvent = struct {
    pub fn GetEventCategory(self: WindowCloseEvent) SystemEventCategory {
        _ = self;
        return .EC_Window;
    }
};

pub const WindowResizeEvent = struct {
    pub fn GetEventCategory(self: WindowResizeEvent) SystemEventCategory {
        _ = self;
        return .EC_Window;
    }
    _Width: usize,
    _Height: usize,
};

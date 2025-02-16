const KeyCodes = @import("../Inputs/KeyCodes.zig").KeyCodes;
const MouseCodes = @import("../Inputs/MouseCodes.zig").MouseCodes;

pub const SystemEventCategory = enum(u8) {
    EC_Default,
    EC_Input,
    EC_Window,
};

pub const SystemEvent = union(enum) {
    ET_DefaultEvent: DefaultEvent,
    ET_WindowClose: WindowCloseEvent,
    ET_WindowResize: WindowResizeEvent,
    ET_KeyPressed: KeyPressedEvent,
    ET_KeyReleased: KeyReleasedEvent,
    ET_MouseButtonPressed: MouseButtonPressedEvent,
    ET_MouseButtonReleased: MouseButtonReleasedEvent,
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

pub const KeyPressedEvent = struct {
    pub fn GetEventCategory(self: KeyPressedEvent) SystemEventCategory {
        _ = self;
        return .EC_Input;
    }
    _KeyCode: KeyCodes,
    _RepeatCount: u32,
};

pub const KeyReleasedEvent = struct {
    pub fn GetEventCategory(self: KeyReleasedEvent) SystemEventCategory {
        _ = self;
        return .EC_Input;
    }
    _KeyCode: KeyCodes,
};

pub const MouseButtonPressedEvent = struct {
    pub fn GetEventCategory(self: MouseButtonPressedEvent) SystemEventCategory {
        _ = self;
        return .EC_Window;
    }
    _MouseCode: MouseCodes,
};

pub const MouseButtonReleasedEvent = struct {
    pub fn GetEventCategory(self: MouseButtonReleasedEvent) SystemEventCategory {
        _ = self;
        return .EC_Input;
    }
    _MouseCode: MouseCodes,
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
    _Width: u32,
    _Height: u32,
};

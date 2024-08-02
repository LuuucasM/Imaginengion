const EventCategory = @import("EventEnums.zig").EventCategory;
const EventType = @import("EventEnums.zig").EventType;
const KeyCodes = @import("../Inputs/KeyCodes.zig").KeyCodes;
const MouseCodes = @import("../Inputs/MouseCodes.zig").MouseCodes;

pub const KeyPressedEvent = struct {
    pub fn GetEventCategory(self: KeyPressedEvent) EventCategory {
        _ = self;
        return .EC_Input;
    }
    _KeyCode: KeyCodes,
    _RepeatCount: u32,
};

pub const KeyReleasedEvent = struct {
    pub fn GetEventCategory(self: KeyReleasedEvent) EventCategory {
        _ = self;
        return .EC_Input;
    }
    _KeyCode: KeyCodes,
};

pub const MouseButtonPressedEvent = struct {
    pub fn GetEventCategory(self: MouseButtonPressedEvent) EventCategory {
        _ = self;
        return .EC_Window;
    }
    _MouseCode: MouseCodes,
};

pub const MouseButtonReleasedEvent = struct {
    pub fn GetEventCategory(self: MouseButtonReleasedEvent) EventCategory {
        _ = self;
        return .EC_Input;
    }
    _MouseCode: MouseCodes,
};

pub const MouseMovedEvent = struct {
    pub fn GetEventCategory(self: MouseMovedEvent) EventCategory {
        _ = self;
        return .EC_Input;
    }
    _MouseX: f32,
    _MouseY: f32,
};

pub const MouseScrolledEvent = struct {
    pub fn GetEventCategory(self: MouseScrolledEvent) EventCategory {
        _ = self;
        return .EC_Input;
    }
    _XOffset: f32,
    _YOffset: f32,
};

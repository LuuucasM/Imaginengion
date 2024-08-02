const EventNames = @import("EventEnums.zig").EventNames;
const KeyCodes = @import("../Inputs/KeyCodes.zig").KeyCodes;
const MouseCodes = @import("../Inputs/MouseCodes.zig").MouseCodes;

pub const KeyPressedEvent = struct {
    pub fn GetEventName(self: KeyPressedEvent) EventNames {
        _ = self;
        return .EN_KeyPressed;
    }
    _KeyCode: KeyCodes,
    _RepeatCount: u32,
};

pub const KeyReleasedEvent = struct {
    pub fn GetEventName(self: KeyReleasedEvent) EventNames {
        _ = self;
        return .EN_KeyReleased;
    }
    _KeyCode: KeyCodes,
};

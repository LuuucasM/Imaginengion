const std = @import("std");
const builtin = @import("builtin");
const MathTypes = @import("../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;
const InputEnums = @import("InputEnums.zig");
const Tracy = @import("../Core/Tracy.zig");
const InputManager = @This();

/// How far the mouse can move between pressing and releasing a button and still count as a click
/// rather than a drag, in window coordinates. A left drag rotates the editor camera, a left click selects.
pub const CLICK_DRAG_THRESHOLD: f32 = 4.0;

/// Indexed by the scan code's value rather than std.EnumSet: ScanCodes has gaps, and EnumSet looks those enums up with
/// a linear scan over every field
const KeySet = std.StaticBitSet(@intFromEnum(InputEnums.ScanCodes.COUNT));
//BUTTON_X2 is the highest button, so this has a bit for each button's value
const MouseSet = std.StaticBitSet(@intFromEnum(InputEnums.MouseCodes.BUTTON_X2) + 1);

_KeyPressedSet: KeySet,
//which of the pressed keys the OS has started repeating. Only ever set for a key that is also in _KeyPressedSet
_KeyRepeatedSet: KeySet,
_MousePressedSet: MouseSet,
_MouseRepeatedSet: MouseSet,
_MousePosition: Vec2(f32),
_MouseScrolled: Vec2(f32),
_MousePositionDelta: Vec2(f32),
_MouseScrolledDelta: Vec2(f32),
//where each button went down, while it is held. Null when it isn't, or once its release was handled
_MouseDownPositions: std.EnumArray(InputEnums.MouseCodes, ?Vec2(f32)),
/// Set while a text input has the keyboard (see FocusSystem): the keys are being typed into it, so IsKeyPressed and
/// IsKeyRepeated read false for everything else, the way a script in a scene under the text field never hears its
/// key events
mKeyboardTaken: bool,

pub const empty: InputManager = .{
    ._KeyPressedSet = .empty,
    ._KeyRepeatedSet = .empty,
    ._MousePressedSet = .empty,
    ._MouseRepeatedSet = .empty,
    ._MousePosition = .{ .x = 0.0, .y = 0.0 },
    ._MouseScrolled = .{ .x = 0.0, .y = 0.0 },
    ._MousePositionDelta = .{ .x = 0.0, .y = 0.0 },
    ._MouseScrolledDelta = .{ .x = 0.0, .y = 0.0 },
    ._MouseDownPositions = .initFill(null),
    .mKeyboardTaken = false,
};

pub fn IsKeyPressed(self: *const InputManager, key: InputEnums.ScanCodes) bool {
    if (self.mKeyboardTaken) return false;
    return self._KeyPressedSet.isSet(@intFromEnum(key));
}
/// Whether the key is down even while a text input has the keyboard, for what is doing the typing (e.g. Ctrl for
/// Ctrl+V)
pub fn IsKeyPressedUnfiltered(self: *const InputManager, key: InputEnums.ScanCodes) bool {
    return self._KeyPressedSet.isSet(@intFromEnum(key));
}
pub fn IsKeyRepeated(self: *const InputManager, key: InputEnums.ScanCodes) bool {
    if (self.mKeyboardTaken) return false;
    return self._KeyRepeatedSet.isSet(@intFromEnum(key));
}
pub fn IsMousePressed(self: *const InputManager, button: InputEnums.MouseCodes) bool {
    return self._MousePressedSet.isSet(@intFromEnum(button));
}
pub fn IsMouseRepeated(self: *const InputManager, button: InputEnums.MouseCodes) bool {
    return self._MouseRepeatedSet.isSet(@intFromEnum(button));
}
pub fn GetMousePosition(self: *const InputManager) Vec2(f32) {
    return self._MousePosition;
}
pub fn GetMousePositionDelta(self: *const InputManager) Vec2(f32) {
    return self._MousePositionDelta;
}
pub fn GetMouseScrolled(self: *const InputManager) Vec2(f32) {
    return self._MouseScrolled;
}
pub fn GetMouseScrolledDelta(self: *const InputManager) Vec2(f32) {
    return self._MouseScrolledDelta;
}

pub fn SetKeyPressed(self: *InputManager, key: InputEnums.ScanCodes) void {
    const index = @intFromEnum(key);
    //a press for a key that is already down is the OS repeating it
    if (self._KeyPressedSet.isSet(index)) self._KeyRepeatedSet.set(index);
    self._KeyPressedSet.set(index);
}

pub fn SetKeyReleased(self: *InputManager, key: InputEnums.ScanCodes) void {
    const index = @intFromEnum(key);
    self._KeyPressedSet.unset(index);
    self._KeyRepeatedSet.unset(index);
}

/// `position` is where the button went down, in window coordinates.
pub fn SetMousePressed(self: *InputManager, button: InputEnums.MouseCodes, position: Vec2(f32)) void {
    const index = @intFromEnum(button);
    if (self._MousePressedSet.isSet(index)) self._MouseRepeatedSet.set(index);
    self._MousePressedSet.set(index);
    self._MouseDownPositions.set(button, position);
}

/// `position` is where the button came up. Returns whether this press and release was a click: it went
/// down and came up within CLICK_DRAG_THRESHOLD of the same spot, rather than dragging somewhere.
pub fn SetMouseReleased(self: *InputManager, button: InputEnums.MouseCodes, position: Vec2(f32)) bool {
    const index = @intFromEnum(button);
    self._MousePressedSet.unset(index);
    self._MouseRepeatedSet.unset(index);

    const down_position = self._MouseDownPositions.get(button) orelse return false;
    self._MouseDownPositions.set(button, null);
    return down_position.Distance(position) < CLICK_DRAG_THRESHOLD;
}

pub fn SetMousePosition(self: *InputManager, new_pos: Vec2(f32)) void {
    self._MousePositionDelta = new_pos.SubVec(self._MousePosition);
    self._MousePosition = new_pos;
}

pub fn SetMouseScrolled(self: *InputManager, new_scrolled: Vec2(f32)) void {
    self._MouseScrolledDelta = new_scrolled.SubVec(self._MouseScrolled);
    self._MouseScrolled = new_scrolled;
}

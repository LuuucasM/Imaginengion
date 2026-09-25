const std = @import("std");
const builtin = @import("builtin");
const MathTypes = @import("../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;
const Set = @import("../Vendor/ziglang-set/src/hash_set/managed.zig").HashSetManaged;
const HashMap = std.AutoHashMapUnmanaged;
const InputEnums = @import("InputEnums.zig");
const Tracy = @import("../Core/Tracy.zig");
const InputManager = @This();

/// How far the mouse can move between pressing and releasing a button and still count as a click
/// rather than a drag, in window coordinates. A left drag rotates the editor camera, a left click selects.
pub const CLICK_DRAG_THRESHOLD: f32 = 4.0;

_KeyPressedSet: HashMap(InputEnums.ScanCodes, u1),
_MousePressedSet: HashMap(InputEnums.MouseCodes, u1),
_MousePosition: Vec2(f32),
_MouseScrolled: Vec2(f32),
_MousePositionDelta: Vec2(f32),
_MouseScrolledDelta: Vec2(f32),
//where each button went down, while it is held. Null when it isn't, or once its release was handled
_MouseDownPositions: std.EnumArray(InputEnums.MouseCodes, ?Vec2(f32)),

pub const empty: InputManager = .{
    ._KeyPressedSet = .empty,
    ._MousePressedSet = .empty,
    ._MousePosition = .{ .x = 0.0, .y = 0.0 },
    ._MouseScrolled = .{ .x = 0.0, .y = 0.0 },
    ._MousePositionDelta = .{ .x = 0.0, .y = 0.0 },
    ._MouseScrolledDelta = .{ .x = 0.0, .y = 0.0 },
    ._MouseDownPositions = .initFill(null),
};

pub fn Init(self: *InputManager, engine_allocator: std.mem.Allocator) !void {
    try self._KeyPressedSet.ensureTotalCapacity(engine_allocator, @typeInfo(InputEnums.ScanCodes).@"enum".field_names.len);
    try self._MousePressedSet.ensureTotalCapacity(engine_allocator, @typeInfo(InputEnums.MouseCodes).@"enum".field_names.len);
}

pub fn Deinit(self: *InputManager, engine_allocator: std.mem.Allocator) void {
    self._KeyPressedSet.deinit(engine_allocator);
    self._MousePressedSet.deinit(engine_allocator);
}

pub fn IsKeyPressed(self: InputManager, key: InputEnums.ScanCodes) bool {
    return self._KeyPressedSet.contains(key);
}
pub fn IsKeyRepeated(self: InputManager, key: InputEnums.ScanCodes) bool {
    if (self._KeyPressedSet.get(key)) |value| {
        return value == 1;
    }
    return false;
}
pub fn IsMousePressed(self: InputManager, button: InputEnums.MouseCodes) bool {
    return self._MousePressedSet.contains(button);
}
pub fn IsMouseRepeated(self: InputManager, button: InputEnums.MouseCodes) bool {
    if (self._MousePressedSet.get(button)) |value| {
        return value == 1;
    }
    return false;
}
pub fn GetMousePosition(self: InputManager) Vec2(f32) {
    return self._MousePosition;
}
pub fn GetMousePositionDelta(self: InputManager) Vec2(f32) {
    return self._MousePositionDelta;
}
pub fn GetMouseScrolled(self: InputManager) Vec2(f32) {
    return self._MouseScrolled;
}
pub fn GetMouseScrolledDelta(self: InputManager) Vec2(f32) {
    return self._MouseScrolledDelta;
}

pub fn SetKeyPressed(self: *InputManager, key: InputEnums.ScanCodes) !void {
    const gop = self._KeyPressedSet.getOrPutAssumeCapacity(key);
    gop.value_ptr.* = if (gop.found_existing) 1 else 0;
}

pub fn SetKeyReleased(self: *InputManager, key: InputEnums.ScanCodes) void {
    _ = self._KeyPressedSet.remove(key);
}

/// `position` is where the button went down, in window coordinates.
pub fn SetMousePressed(self: *InputManager, button: InputEnums.MouseCodes, position: Vec2(f32)) !void {
    const gop = self._MousePressedSet.getOrPutAssumeCapacity(button);
    gop.value_ptr.* = if (gop.found_existing) 1 else 0;
    self._MouseDownPositions.set(button, position);
}

/// `position` is where the button came up. Returns whether this press and release was a click: it went
/// down and came up within CLICK_DRAG_THRESHOLD of the same spot, rather than dragging somewhere.
pub fn SetMouseReleased(self: *InputManager, button: InputEnums.MouseCodes, position: Vec2(f32)) bool {
    _ = self._MousePressedSet.remove(button);

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

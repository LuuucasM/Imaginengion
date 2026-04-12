const std = @import("std");
const builtin = @import("builtin");
const LinAlg = @import("../Math/LinAlg.zig");
const Vec2f32 = LinAlg.Vec2f32;
const Set = @import("../Vendor/ziglang-set/src/hash_set/managed.zig").HashSetManaged;
const HashMap = std.AutoHashMapUnmanaged;
const InputEnums = @import("InputEnums.zig");
const Tracy = @import("../Core/Tracy.zig");
const InputManager = @This();

_KeyPressedSet: HashMap(InputEnums.ScanCodes, u1),
_MousePressedSet: HashMap(InputEnums.MouseCodes, u1),
_MousePosition: Vec2f32,
_MouseScrolled: Vec2f32,
_MousePositionDelta: Vec2f32,
_MouseScrolledDelta: Vec2f32,

pub const empty: InputManager = .{
    ._KeyPressedSet = .empty,
    ._MousePressedSet = .empty,
    ._MousePosition = Vec2f32{ 0.0, 0.0 },
    ._MouseScrolled = Vec2f32{ 0.0, 0.0 },
    ._MousePositionDelta = Vec2f32{ 0.0, 0.0 },
    ._MouseScrolledDelta = Vec2f32{ 0.0, 0.0 },
};

pub fn Init(self: *InputManager, engine_allocator: std.mem.Allocator) void {
    self._KeyPressedSet.ensureTotalCapacity(engine_allocator, @typeInfo(InputEnums.ScanCodes).@"enum".fields.len);
    self._MousePressedSet.ensureTotalCapacity(engine_allocator, @typeInfo(InputEnums.MouseCodes).@"enum".fields.len);
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
pub fn GetMousePosition(self: *InputManager) Vec2f32 {
    return self._MousePosition;
}
pub fn GetMousePositionDelta(self: *InputManager) Vec2f32 {
    return self._MousePositionDelta;
}
pub fn GetMouseScrolled(self: *InputManager) Vec2f32 {
    return self._MouseScrolled;
}
pub fn GetMouseScrolledDelta(self: *InputManager) Vec2f32 {
    return self._MouseScrolledDelta;
}

pub fn SetKeyPressed(self: *InputManager, key: InputEnums.ScanCodes) !void {
    if (self._KeyPressedSet.contains(key) == true) {
        try self._KeyPressedSet.putAssumeCapacity(key, 1);
    } else {
        try self._KeyPressedSet.putAssumeCapacity(key, 0);
    }
}

pub fn SetKeyReleased(self: *InputManager, key: InputEnums.ScanCodes) void {
    _ = self._KeyPressedSet.remove(key);
}

pub fn SetMousePressed(self: *InputManager, button: InputEnums.MouseCodes) !void {
    if (self._MousePressedSet.contains(button) == true) {
        try self._MousePressedSet.putAssumeCapacity(button, 1);
    } else {
        try self._MousePressedSet.putAssumeCapacity(button, 0);
    }
}

pub fn SetMousePosition(self: *InputManager, new_pos: Vec2f32) void {
    self._MousePositionDelta = new_pos - self._MousePosition;
    self._MousePosition = new_pos;
}

pub fn SetMouseScrolled(self: *InputManager, new_scrolled: Vec2f32) void {
    self._MouseScrolledDelta = new_scrolled - self._MouseScrolled;
    self._MouseScrolled = new_scrolled;
}

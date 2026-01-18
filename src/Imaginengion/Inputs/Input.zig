const std = @import("std");
const builtin = @import("builtin");
const LinAlg = @import("../Math/LinAlg.zig");
const Vec2f32 = LinAlg.Vec2f32;
const Set = @import("../Vendor/ziglang-set/src/hash_set/managed.zig").HashSetManaged;
const HashMap = std.AutoHashMap;
const InputCodes = @import("InputCodes.zig").InputCodes;
const Tracy = @import("../Core/Tracy.zig");
const InputManager = @This();

pub const InputPress = struct {
    mInputCode: InputCodes,
    mTimestamp: i32,
};

_InputPressedSet: HashMap(InputCodes, u1) = undefined,
_MousePosition: Vec2f32 = Vec2f32{ 0.0, 0.0 },
_MouseScrolled: Vec2f32 = Vec2f32{ 0.0, 0.0 },
_MousePositionDelta: Vec2f32 = Vec2f32{ 0.0, 0.0 },
_MouseScrolledDelta: Vec2f32 = Vec2f32{ 0.0, 0.0 },

pub fn Init(self: *InputManager, engine_allocator: std.mem.Allocator) void {
    self._InputPressedSet = HashMap(InputCodes, u1).init(engine_allocator);
}
pub fn Deinit(self: *InputManager) void {
    self._InputPressedSet.deinit();
}

pub fn IsInputPressed(self: *InputManager, key: InputCodes) bool {
    return self._InputPressedSet.contains(key);
}
pub fn IsInputRepeated(self: *InputManager, key: InputCodes) bool {
    if (self._InputPressedSet.get(key)) |value| {
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

pub fn SetInputPressed(self: *InputManager, input: InputCodes) !void {
    if (self._InputPressedSet.contains(input) == true) {
        try self._InputPressedSet.put(input, 1);
    } else {
        try self._InputPressedSet.put(input, 0);
    }
}

pub fn SetInputReleased(self: *InputManager, input: InputCodes) void {
    _ = self._InputPressedSet.remove(input);
}

pub fn SetMousePosition(self: *InputManager, new_pos: Vec2f32) void {
    self._MousePositionDelta = new_pos - self._MousePosition;
    self._MousePosition = new_pos;
}

pub fn SetMouseScrolled(self: *InputManager, new_scrolled: Vec2f32) void {
    self._MouseScrolledDelta = new_scrolled - self._MouseScrolled;
    self._MouseScrolled = new_scrolled;
}

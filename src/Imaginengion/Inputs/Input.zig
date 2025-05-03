const std = @import("std");
const builtin = @import("builtin");
const LinAlg = @import("../Math/LinAlg.zig");
const Vec2f32 = LinAlg.Vec2f32;
const Set = @import("../Vendor/ziglang-set/src/hash_set/managed.zig").HashSetManaged;
const HashMap = std.AutoHashMap;
const KeyCodes = @import("KeyCodes.zig").KeyCodes;
const MouseCodes = @import("MouseCodes.zig").MouseCodes;
const Input = @This();

var InputManager: Input = Input{};

_KeyPressedSet: HashMap(KeyCodes, u1) = undefined,
_MousePressedSet: HashMap(MouseCodes, u1) = undefined,
_MousePosition: Vec2f32 = std.mem.zeroes(Vec2f32),
_MouseScrolled: Vec2f32 = std.mem.zeroes(Vec2f32),

var InputGPA = std.heap.DebugAllocator(.{}).init;

pub fn Init() !void {
    InputManager._KeyPressedSet = HashMap(KeyCodes, u1).init(InputGPA.allocator());
    InputManager._MousePressedSet = HashMap(MouseCodes, u1).init(InputGPA.allocator());
}
pub fn Deinit() void {
    InputManager._KeyPressedSet.deinit();
    InputManager._MousePressedSet.deinit();
    _ = InputGPA.deinit();
}

pub fn GetInstance() *Input {
    return &InputManager;
}

pub fn SetKeyPressed(key: KeyCodes) !void {
    if (InputManager._KeyPressedSet.contains(key) == true) {
        try InputManager._KeyPressedSet.put(key, 1);
    } else {
        try InputManager._KeyPressedSet.put(key, 0);
    }
}

pub fn SetKeyReleased(key: KeyCodes) void {
    _ = InputManager._KeyPressedSet.remove(key);
}
pub fn IsKeyPressed(key: KeyCodes) bool {
    return InputManager._KeyPressedSet.contains(key);
}
pub fn SetMousePressed(button: MouseCodes) !void {
    if (InputManager._MousePressedSet.contains(button) == true) {
        try InputManager._MousePressedSet.put(button, 1);
    } else {
        try InputManager._MousePressedSet.put(button, 0);
    }
}
pub fn SetMouseReleased(button: MouseCodes) void {
    _ = InputManager._MousePressedSet.remove(button);
}
pub fn IsMouseButtonPressed(button: MouseCodes) bool {
    return InputManager._MousePressedSet.contains(button);
}
pub fn SetMousePosition(newPos: Vec2f32) void {
    InputManager._MousePosition = newPos;
}
pub fn GetMousePosition() Vec2f32 {
    return InputManager._MousePosition;
}
pub fn SetMouseScrolled(newScrolled: Vec2f32) void {
    InputManager._MouseScrolled = newScrolled;
}
pub fn GetMouseScrolled() Vec2f32 {
    return InputManager._MouseScrolled;
}

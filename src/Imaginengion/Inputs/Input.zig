const std = @import("std");
const builtin = @import("builtin");
const LinAlg = @import("../Math/LinAlg.zig");
const Vec2f32 = LinAlg.Vec2f32;
const Set = @import("../Vendor/ziglang-set/src/hash_set/managed.zig").HashSetManaged;
const HashMap = std.AutoHashMap;
const KeyCodes = @import("KeyCodes.zig").KeyCodes;
const MouseCodes = @import("MouseCodes.zig").MouseCodes;

var StaticInputContext: InputContext = InputContext{};

pub const InputContext = struct {
    _KeyPressedSet: HashMap(KeyCodes, u1) = undefined,
    _MousePressedSet: HashMap(MouseCodes, u1) = undefined,
    _MousePosition: Vec2f32 = std.mem.zeroes(Vec2f32),
    _MouseScrolled: Vec2f32 = std.mem.zeroes(Vec2f32),
    pub fn IsKeyPressed(self: *InputContext, key: KeyCodes) bool {
        return self._KeyPressedSet.contains(key);
    }
    pub fn IsMouseButtonPressed(self: *InputContext, button: MouseCodes) bool {
        return self._MousePressedSet.contains(button);
    }
    pub fn GetMousePosition(self: *InputContext) Vec2f32 {
        return self._MousePosition;
    }
    pub fn GetMouseScrolled(self: *InputContext) Vec2f32 {
        return self._MouseScrolled;
    }
};

var InputGPA = std.heap.DebugAllocator(.{}).init;

pub fn Init() !void {
    StaticInputContext._KeyPressedSet = HashMap(KeyCodes, u1).init(InputGPA.allocator());
    StaticInputContext._MousePressedSet = HashMap(MouseCodes, u1).init(InputGPA.allocator());
}
pub fn Deinit() void {
    StaticInputContext._KeyPressedSet.deinit();
    StaticInputContext._MousePressedSet.deinit();
    _ = InputGPA.deinit();
}

pub fn GetInstance() *InputContext {
    return &StaticInputContext;
}

pub fn SetKeyPressed(key: KeyCodes) !void {
    if (StaticInputContext._KeyPressedSet.contains(key) == true) {
        try StaticInputContext._KeyPressedSet.put(key, 1);
    } else {
        try StaticInputContext._KeyPressedSet.put(key, 0);
    }
}

pub fn SetKeyReleased(key: KeyCodes) void {
    _ = StaticInputContext._KeyPressedSet.remove(key);
}
pub fn IsKeyPressed(key: KeyCodes) bool {
    return StaticInputContext._KeyPressedSet.contains(key);
}
pub fn SetMousePressed(button: MouseCodes) !void {
    if (StaticInputContext._MousePressedSet.contains(button) == true) {
        try StaticInputContext._MousePressedSet.put(button, 1);
    } else {
        try StaticInputContext._MousePressedSet.put(button, 0);
    }
}
pub fn SetMouseReleased(button: MouseCodes) void {
    _ = StaticInputContext._MousePressedSet.remove(button);
}
pub fn IsMouseButtonPressed(button: MouseCodes) bool {
    return StaticInputContext._MousePressedSet.contains(button);
}
pub fn SetMousePosition(newPos: Vec2f32) void {
    StaticInputContext._MousePosition = newPos;
}
pub fn GetMousePosition() Vec2f32 {
    return StaticInputContext._MousePosition;
}
pub fn SetMouseScrolled(newScrolled: Vec2f32) void {
    StaticInputContext._MouseScrolled = newScrolled;
}
pub fn GetMouseScrolled() Vec2f32 {
    return StaticInputContext._MouseScrolled;
}

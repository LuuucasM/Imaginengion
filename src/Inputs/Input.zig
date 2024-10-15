const std = @import("std");
const builtin = @import("builtin");
const LinAlg = @import("../Math/LinAlg.zig");
const Vec2f32 = LinAlg.Vec2f32;
const Set = @import("../Vendor/ziglang-set/src/hash_set/managed.zig").HashSetManaged;
const HashMap = std.AutoHashMap;
const KeyCodes = @import("KeyCodes.zig").KeyCodes;
const MouseCodes = @import("MouseCodes.zig").MouseCodes;
const Input = @This();

var InputManager: *Input = undefined;

_EngineAllocator: std.mem.Allocator,

_KeyPressedSet: HashMap(KeyCodes, u32),
_MousePressedSet: Set(MouseCodes),
_MousePosition: Vec2f32,
_MouseScrolled: Vec2f32,

var InputGPA: std.heap.GeneralPurposeAllocator(.{}) = std.heap.GeneralPurposeAllocator(.{}){};

pub fn Init(EngineAllocator: std.mem.Allocator) !void {
    InputManager = try EngineAllocator.create(Input);
    InputManager.* = .{
        ._EngineAllocator = EngineAllocator,
        ._KeyPressedSet = HashMap(KeyCodes, u32).init(InputGPA.allocator()),
        ._MousePressedSet = Set(MouseCodes).init(InputGPA.allocator()),
        ._MousePosition = std.mem.zeroes(Vec2f32),
        ._MouseScrolled = std.mem.zeroes(Vec2f32),
    };
}
pub fn Deinit() void {
    InputManager._KeyPressedSet.deinit();
    InputManager._MousePressedSet.deinit();
    _ = InputGPA.deinit();
    InputManager._EngineAllocator.destroy(InputManager);
}

pub fn SetKeyPressed(key: KeyCodes, on: bool) !void {
    if (on == true) {
        if (InputManager._KeyPressedSet.contains(key)) {
            const result = try InputManager._KeyPressedSet.getOrPut(key);
            if (result.found_existing) {
                result.value_ptr.* = 1;
            }
        } else {
            try InputManager._KeyPressedSet.put(key, 0);
        }
    } else {
        if (InputManager._KeyPressedSet.contains(key)) {
            _ = InputManager._KeyPressedSet.remove(key);
        }
    }
}
pub fn IsKeyPressed(key: KeyCodes) bool {
    return if (InputManager._KeyPressedSet.contains(key)) true else false;
}
pub fn SetMousePressed(button: MouseCodes, on: bool) !void {
    if (on == true) {
        _ = try InputManager._MousePressedSet.add(button);
    } else {
        if (InputManager._MousePressedSet.contains(button)) {
            _ = InputManager._MousePressedSet.remove(button);
        }
    }
}
pub fn IsMouseButtonPressed(button: MouseCodes) bool {
    return if (InputManager._MousePressedSet.contains(button)) true else false;
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
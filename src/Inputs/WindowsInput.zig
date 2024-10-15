const std = @import("std");
const Vec2f32 = @import("../Math/LinAlg.zig").Vec2f32;
const Set = @import("../Vendor/ziglang-set/src/hash_set/managed.zig").HashSetManaged;
const HashMap = std.AutoHashMap;
const KeyCodes = @import("KeyCodes.zig").KeyCodes;
const MouseCodes = @import("MouseCodes.zig").MouseCodes;
const WindowsInput = @This();

const glfw = @import("../Core/CImports.zig").glfw;

var InputGPA: std.heap.GeneralPurposeAllocator(.{}) = std.heap.GeneralPurposeAllocator(.{}){};

_KeyPressedSet: HashMap(KeyCodes, u32),
_MousePressedSet: Set(MouseCodes),
_MousePosition: Vec2f32,
_MouseScrolled: Vec2f32,
_Window: *anyopaque,

pub fn Init(window: *anyopaque) WindowsInput {
    return WindowsInput{
        ._KeyPressedSet = HashMap(KeyCodes, u32).init(InputGPA.allocator()),
        ._MousePressedSet = Set(MouseCodes).init(InputGPA.allocator()),
        ._MousePosition = std.mem.zeroes(Vec2f32),
        ._MouseScrolled = std.mem.zeroes(Vec2f32),
        ._Window = window,
    };
}
pub fn Deinit(self: *WindowsInput) void {
    self._KeyPressedSet.deinit();
    self._MousePressedSet.deinit();
    _ = InputGPA.deinit();
}
pub fn SetKeyPressed(self: *WindowsInput, key: KeyCodes, on: bool) !void {
    if (on == true) {
        if (self._KeyPressedSet.contains(key)) {
            const result = try self._KeyPressedSet.getOrPut(key);
            if (result.found_existing) {
                result.value_ptr.* = 1;
            }
        } else {
            try self._KeyPressedSet.put(key, 0);
        }
    } else {
        if (self._KeyPressedSet.contains(key)) {
            _ = self._KeyPressedSet.remove(key);
        }
    }
}
pub fn IsKeyPressed(self: WindowsInput, key: KeyCodes) bool {
    return if (self._KeyPressedSet.contains(key)) true else false;
}
pub fn SetMousePressed(self: *WindowsInput, button: MouseCodes, on: bool) !void {
    if (on == true) {
        _ = try self._MousePressedSet.add(button);
    } else {
        if (self._MousePressedSet.contains(button)) {
            _ = self._MousePressedSet.remove(button);
        }
    }
}
pub fn IsMouseButtonPressed(self: WindowsInput, button: MouseCodes) bool {
    return if (self._MousePressedSet.contains(button)) true else false;
}
pub fn SetMousePosition(self: *WindowsInput, newPos: Vec2f32) void {
    self._MousePosition = newPos;
}
pub fn GetMousePosition(self: WindowsInput) Vec2f32 {
    return self._MousePosition;
}
pub fn SetMouseScrolled(self: *WindowsInput, newScrolled: Vec2f32) void {
    self._MouseScrolled = newScrolled;
}
pub fn GetMouseScrolled(self: WindowsInput) Vec2f32 {
    return self._MouseScrolled;
}
pub fn PollInputEvents(self: WindowsInput) void {
    _ = self;
    glfw.glfwPollEvents();
}

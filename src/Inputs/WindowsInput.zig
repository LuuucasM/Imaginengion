const std = @import("std");
const Set = @import("../Vendor/ziglang-set/src/hash_set/managed.zig").HashSetManaged;
const HashMap = @import("std").HashMap;
const KeyCodes = @import("KeyCodes.zig").KeyCodes;
const MouseCodes = @import("MouseCodes.zig").MouseCodes;
const WindowsInput = @This();

const glfw = @import("../Core/CImports.zig").glfw;

_KeyPressedSet: HashMap(KeyCodes, u32, std.hash_map.AutoContext(KeyCodes), std.hash_map.default_max_load_percentage) = undefined,
_MousePressedSet: Set(MouseCodes) = undefined,
_MousePosition: @Vector(2, f64) = @splat(0),
_MouseScrolled: @Vector(2, f64) = @splat(0),
_Allocator: std.mem.Allocator = std.heap.page_allocator,
_Window: *void = undefined,

pub fn Init(self: *WindowsInput, window: *void) void {
    self._Window = window;
    self._KeyPressedSet = HashMap(KeyCodes, u32, std.hash_map.AutoContext(KeyCodes), std.hash_map.default_max_load_percentage).init(self._Allocator);
    self._MousePressedSet = Set(MouseCodes).init(self._Allocator);
}
pub fn Deinit(self: *WindowsInput) void {
    self._KeyPressedSet.deinit();
    self._MousePressedSet.deinit();
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
pub fn SetMousePosition(self: *WindowsInput, newPos: @Vector(2, f64)) void {
    self._MousePosition = newPos;
}
pub fn GetMousePosition(self: WindowsInput) @Vector(2, f64) {
    return self._MousePosition;
}
pub fn SetMouseScrolled(self: *WindowsInput, newScrolled: @Vector(2, f64)) void {
    self._MouseScrolled = newScrolled;
}
pub fn GetMouseScrolled(self: WindowsInput) @Vector(2, f64) {
    return self._MouseScrolled;
}
pub fn PollInputEvents(self: WindowsInput) void {
    _ = self;
    glfw.glfwPollEvents();
}

const std = @import("std");
const Set = @import("../Vendor/ziglang-set/src/hash_set/managed.zig").HashSetManaged;
const HashMap = @import("std").HashMap;
const KeyCodes = @import("KeyCodes.zig").KeyCodes;
const MouseCodes = @import("MouseCodes.zig").MouseCodes;
const WindowsInput = @This();

const glfw = @import("../Core/CImports.zig").glfw;
_KeyPressedSet: HashMap(u16, u32, std.hash_map.AutoContext(u16), std.hash_map.default_max_load_percentage) = undefined,
_KeyReleasedSet: Set(u16) = undefined,
_MousePressedSet: Set(u16) = undefined,
_MouseReleasedSet: Set(u16) = undefined,
_MousePosition: @Vector(2, u32) = @splat(0),
_MouseScrolled: @Vector(2, u32) = @splat(0),
_Mutex: std.Thread.Mutex = .{},
_Allocator: std.mem.Allocator = std.heap.page_allocator,
_Window: *void = undefined,

pub fn Init(self: *WindowsInput, window: *void) void {
    self._Window = window;
    self._KeyPressedSet.init(self._Allocator);
    self._KeyReleasedSet.init(self._Allocator);
    self._MousePressedSet.init(self._Allocator);
    self._MouseReleasedSet.init(self._Allocator);
}
pub fn SetKeyPressed(self: WindowsInput, key: KeyCodes, on: bool) void {
    const key_num = @intFromEnum(key);
    self._Mutex.lock();
    defer self._Mutex.unlock();
    if (on == true) {
        if (self._KeyPressedSet.contains(key_num)) {
            const result = try self._KeyPressedSet.getOrPut(key_num);
            if (result.found_existing) {
                result.value_ptr.* += 1;
            }
        } else if (self._KeyReleasedSet.contains(key_num)) {
            self._KeyReleasedSet.remove(key_num);
        } else {
            self._KeyPressedSet.put(key, 0);
        }
    } else {
        if (self._KeyPressedSet.contains(key_num)) {
            self._KeyPressedSet.remove(key_num);
        } else {
            self._KeyReleasedSet.add(key_num);
        }
    }
}
pub fn IsKeyPressed(self: WindowsInput, key: KeyCodes) bool {
    self._Mutex.lock();
    defer self._Mutex.unlock();
    return if (self._KeyPressedSet.contains(@intFromEnum(key))) true else false;
}
pub fn SetMousePressed(self: WindowsInput, button: MouseCodes, on: bool) void {
    const button_num = @intFromEnum(button);
    self._Mutex.lock();
    defer self._Mutex.unlock();
    if (on == true) {
        if (self._MouseReleasedSet.contains(button_num)) {
            self._MouseReleasedSet.remove(button_num);
        } else {
            self._MousePressedSet.add(button_num);
        }
    } else {
        if (self._MousePressedSet.contains(button_num)) {
            self._MousePressedSet.remove(button_num);
        } else {
            self._MouseReleasedSet.add(button_num);
        }
    }
}
pub fn IsMouseButtonPressed(self: WindowsInput, button: MouseCodes) bool {
    self._Mutex.lock();
    defer self._Mutex.unlock();
    return if (self._MousePressedSet.ocntains(@intFromEnum(button))) true else false;
}
pub fn SetMousePosition(self: WindowsInput, newPos: @Vector(2, f32)) void {
    self._Mutex.lock();
    defer self._Mutex.unlock();
    self._MousePosition = newPos;
}
pub fn GetMousePosition(self: WindowsInput) @Vector(2, f32) {
    self._Mutex.lock();
    defer self._Mutex.unlock();
    return self._MousePosition;
}
pub fn SetMouseScrolled(self: WindowsInput, newScrolled: @Vector(2, f32)) void {
    self._Mutex.lock();
    defer self._Mutex.unlock();
    self._MouseScrolled = newScrolled;
}
pub fn GetMouseScrolled(self: WindowsInput) @Vector(2, f32) {
    self._Mutex.lock();
    defer self._Mutex.unlock();
    return self._MouseScrolled;
}
pub fn PollInputEvents(self: WindowsInput) void {
    _ = self;
    glfw.glfwPollEvents();
}

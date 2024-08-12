const std = @import("std");
const Vec2f32 = @import("../Math/LinAlg.zig").Vec2f32;
const KeyCodes = @import("KeyCodes.zig").KeyCodes;
const MouseCodes = @import("MouseCodes.zig").MouseCodes;
const builtin = @import("builtin");
const UnsupportedInput = @This();

pub fn Init(EngineAllocator: std.mem.Allocator, window: *void) void {
    _ = window;
    _ = EngineAllocator;
    Unsupported();
}

pub fn Deinit(self: UnsupportedInput) void {
    _ = self;
    Unsupported();
}
pub fn SetKeyPressed(self: UnsupportedInput, key: KeyCodes, on: bool) void {
    _ = self;
    _ = key;
    _ = on;
    Unsupported();
}
pub fn IsKeyPressed(self: UnsupportedInput, key: KeyCodes) bool {
    _ = self;
    _ = key;
    return Unsupported();
}
pub fn SetMousePressed(self: UnsupportedInput, button: MouseCodes, on: bool) void {
    _ = self;
    _ = button;
    _ = on;
    Unsupported();
}
pub fn IsMouseButtonPressed(self: UnsupportedInput, button: MouseCodes) bool {
    _ = self;
    _ = button;
    return Unsupported();
}
pub fn SetMousePosition(self: UnsupportedInput, newPos: Vec2f32) void {
    _ = self;
    _ = newPos;
    Unsupported();
}
pub fn GetMousePosition(self: UnsupportedInput) Vec2f32 {
    _ = self;
    return Unsupported();
}
pub fn SetMouseScrolled(self: UnsupportedInput, newScrolled: Vec2f32) void {
    _ = self;
    _ = newScrolled;
    Unsupported();
}
pub fn GetMouseScrolled(self: UnsupportedInput) Vec2f32 {
    _ = self;
    return Unsupported();
}
pub fn PollInputEvents(self: UnsupportedInput) void {
    _ = self;
    Unsupported();
}
fn Unsupported() noreturn {
    @compileError("Unsupported Operating system: " ++ @tagName(builtin.os.tag) ++ " in Input\n");
}

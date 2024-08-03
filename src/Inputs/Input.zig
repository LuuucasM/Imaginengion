const std = @import("std");
const builtin = @import("builtin");

const KeyCodes = @import("KeyCodes.zig").KeyCodes;
const MouseCodes = @import("MouseCodes.zig").MouseCodes;
const Input = @This();

const Impl = switch (builtin.os.tag) {
    .windows => @import("WindowsInput.zig"),
    else => @import("UnsupportedInput.zig"),
};

var InputManager: *Input = undefined;

_Impl: Impl,
_EngineAllocator: std.mem.Allocator,

pub fn Init(EngineAllocator: std.mem.Allocator, window: *void) !void {
    InputManager = try EngineAllocator.create(Input);
    InputManager.* = .{
        ._Impl = .{},
        ._EngineAllocator = EngineAllocator,
    };
    InputManager._Impl.Init(window);
}
pub fn Deinit() void {
    InputManager._Impl.Deinit();
    InputManager._EngineAllocator.destroy(InputManager);
}
pub fn SetKeyPressed(key: KeyCodes, on: bool) !void {
    try InputManager._Impl.SetKeyPressed(key, on);
}
pub fn IsKeyPressed(key: KeyCodes) bool {
    return InputManager._Impl.IsKeyPressed(key);
}
pub fn SetMousePressed(button: MouseCodes, on: bool) !void {
    try InputManager._Impl.SetMousePressed(button, on);
}
pub fn IsMouseButtonPressed(button: MouseCodes) bool {
    return InputManager._Impl.IsMouseButtonPressed(button);
}
pub fn SetMousePosition(newPos: @Vector(2, f64)) void {
    InputManager._Impl.SetMousePosition(newPos);
}
pub fn GetMousePosition() @Vector(2, f64) {
    return InputManager._Impl.GetMousePosition();
}
pub fn SetMouseScrolled(scrolled: @Vector(2, f64)) void {
    InputManager._Impl.SetMouseScrolled(scrolled);
}
pub fn GetMouseScrolled() @Vector(2, f64) {
    return InputManager._Impl.GetMouseScrolled();
}
pub fn PollInputEvents() void {
    InputManager._Impl.PollInputEvents();
}

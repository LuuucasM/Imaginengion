const std = @import("std");
const builtin = @import("builtin");

const KeyCode = @import("Keycodes.zig").KeyCodes;
const MouseCode = @import("Mousecodes.zig").MouseCodes;
const Input = @This();

const Impl = switch (builtin.os.tag) {
    .windows => @import("WindowsInput.zig"),
    else => @import("UnsupportedInput.zig"),
};

var INPUT: *Input = undefined;

_Impl: Impl,
_EngineAllocator: std.mem.Allocator,

pub fn Init(EngineAllocator: std.mem.Allocator, window: *void) void {
    INPUT = try EngineAllocator.create(Input);
    INPUT.* = .{
        ._Impl = .{},
        ._EngineAllocator = EngineAllocator,
    };
    INPUT._Impl.Init(window);
}
//TODO: REMOVE ALL THE REFERENCES TO SELF. I FORGOT THAT
//TODO: I NEEDED TO MAKE INPUT A 'STATIC CLASS' AND ACCIDENTLY MADE ALL THE FUNCTIONS
//TODO: CALLED BY REFERENCE OOPS
//TODO: ALSO I FORGOT TO WRITE DEINIT FOR WINDOWSINPUT !
pub fn Deinit(self: *Input) void {
    self._Impl.Deinit();
    self._EngineAllocator.destroy(self);
}
pub fn SetKeyPressed(self: Input, key: KeyCode, on: bool) void {
    self._Impl.SetKeyPressed(key, on);
}
pub fn IsKeyPressed(self: Input, key: KeyCode) bool {
    return self._Impl.IsKeyPressed(key);
}
pub fn SetMousePressed(self: Input, button: MouseCode, on: bool) void {
    self._Impl.SetMousePressed(button, on);
}
pub fn IsMouseButtonPressed(self: Input, button: MouseCode) bool {
    return self._Impl.IsMouseButtonPressed(button);
}
pub fn SetMousePosition(self: Input, newPos: @Vector(2, f32)) void {
    self._Impl.SetMousePosition(newPos);
}
pub fn GetMousePosition(self: Input) @Vector(2, f32) {
    return self._Impl.GetMousePosition();
}
pub fn SetMouseScrolled(self: Input, scrolled: @Vector(2, f32)) void {
    self._Impl.SetMouseScrolled(scrolled);
}
pub fn GetMouseScrolled(self: Input) @Vector(2, f32) {
    return self._Impl.GetMouseScrolled();
}
pub fn PollInputEvents(self: Input) void {
    self._Impl.PollInputEvents();
}

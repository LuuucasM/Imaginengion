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

pub fn Init(EngineAllocator: std.mem.Allocator, window: *void) !void {
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
pub fn Deinit() void {
    INPUT._Impl.Deinit();
    INPUT._EngineAllocator.destroy(INPUT);
}
pub fn SetKeyPressed(key: KeyCode, on: bool) void {
    INPUT._Impl.SetKeyPressed(key, on);
}
pub fn IsKeyPressed(key: KeyCode) bool {
    return INPUT._Impl.IsKeyPressed(key);
}
pub fn SetMousePressed(button: MouseCode, on: bool) void {
    INPUT._Impl.SetMousePressed(button, on);
}
pub fn IsMouseButtonPressed(button: MouseCode) bool {
    return INPUT._Impl.IsMouseButtonPressed(button);
}
pub fn SetMousePosition(newPos: @Vector(2, f32)) void {
    INPUT._Impl.SetMousePosition(newPos);
}
pub fn GetMousePosition() @Vector(2, f32) {
    return INPUT._Impl.GetMousePosition();
}
pub fn SetMouseScrolled(scrolled: @Vector(2, f32)) void {
    INPUT._Impl.SetMouseScrolled(scrolled);
}
pub fn GetMouseScrolled() @Vector(2, f32) {
    return INPUT._Impl.GetMouseScrolled();
}
pub fn PollInputEvents() void {
    INPUT._Impl.PollInputEvents();
}

const builtin = @import("builtin");
const UnsupportedInput = @This();

pub fn Init(window: *void) void {
    _ = window;
    Unsupported();
}

pub fn Deinit(self: UnsupportedInput) void {
    _ = self;
    Unsupported();
}
pub fn SetKeyPressed(self: UnsupportedInput) void {
    _ = self;
    Unsupported();
}
pub fn IsKeyPressed(self: UnsupportedInput) bool {
    _ = self;
    return Unsupported();
}
pub fn SetMousePressed(self: UnsupportedInput) void {
    _ = self;
    Unsupported();
}
pub fn IsMouseButtonPressed(self: UnsupportedInput) bool {
    _ = self;
    return Unsupported();
}
pub fn SetMousePosition(self: UnsupportedInput) void {
    _ = self;
    Unsupported();
}
pub fn GetMousePosition(self: UnsupportedInput) @Vector(2, f32) {
    _ = self;
    return Unsupported();
}
pub fn SetMouseScrolled(self: UnsupportedInput) void {
    _ = self;
    Unsupported();
}
pub fn GetMouseScrolled(self: UnsupportedInput) @Vector(2, f32) {
    _ = self;
    return Unsupported();
}
pub fn PollInputEvents(self: UnsupportedInput) void {
    _ = self;
    Unsupported();
}
fn Unsupported() noreturn {
    @compileError("Unsupported Operating system: " ++ @tagName(builtin.os.tag));
}

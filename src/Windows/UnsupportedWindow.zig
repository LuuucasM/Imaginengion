const builtin = @import("builtin");
const UnsupportedWindow = @This();

pub fn Init(self: UnsupportedWindow) UnsupportedWindow {
    _ = self;
    Unsupported();
}

pub fn Deinit(self: UnsupportedWindow) void {
    _ = self;
    Unsupported();
}

pub fn GetWidth(self: UnsupportedWindow) usize {
    _ = self;
    return Unsupported();
}

pub fn GetHeight(self: UnsupportedWindow) usize {
    _ = self;
    return Unsupported();
}

pub fn SetVSync(self: UnsupportedWindow, useVSync: bool) void {
    _ = self;
    _ = useVSync;
    Unsupported();
}

pub fn IsVSync(self: UnsupportedWindow) bool {
    _ = self;
    return Unsupported();
}

pub fn GetNativeWindow(self: UnsupportedWindow) *anyopaque {
    _ = self;
    return Unsupported();
}

pub fn OnWindowResize(self: UnsupportedWindow, width: usize, height: usize) void {
    _ = self;
    _ = width;
    _ = height;
    Unsupported();
}

pub fn PollInputEvents(self: UnsupportedWindow) void {
    _ = self;
    Unsupported();
}

fn Unsupported() noreturn {
    @compileError("Unsupported operating system: " ++ @tagName(builtin.os.tag) ++ " in Window\n");
}

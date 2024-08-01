const glfw = @import("../Core/CImports.zig").glfw;
const WindowsWindow = @This();

_Title: [*:0]const u8,
_Width: usize = 1280,
_Height: usize = 720,
_IsVSync: bool = false,
_WindowCount: usize = 0,
_Window: ?*glfw.struct_GLFWwindow,

pub fn init(self: *WindowsWindow) void {
    _ = self;
}

pub fn deinit(self: *WindowsWindow) void {
    _ = self;
}

pub fn GetWidth(self: *WindowsWindow) usize {
    _ = self;
}

pub fn GetHeight(self: *WindowsWindow) usize {
    _ = self;
}

pub fn SetVSync(self: *WindowsWindow, useVSync: bool) void {
    _ = self;
    _ = useVSync; //TODO
}

pub fn IsVSync(self: *WindowsWindow) bool {
    _ = self;
}

pub fn GetNativeWindow(self: *WindowsWindow) *void {
    _ = self;
}

pub fn OnWindowResize(self: *WindowsWindow) void {
    _ = self;
}

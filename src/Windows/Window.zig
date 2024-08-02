const std = @import("std");
const builtin = @import("builtin");
const Window = @This();

const Impl = switch (builtin.os.tag) {
    .windows => @import("WindowsWindow.zig"),
    else => @import("UnsupportedWindow.zig"),
};

_Impl: Impl,
_EngineAllocator: std.mem.Allocator,

pub fn Init(EngineAllocator: std.mem.Allocator) !*Window {
    const window = try EngineAllocator.create(Window);
    window.* = .{
        ._Impl = .{},
        ._EngineAllocator = EngineAllocator,
    };
    window._Impl.Init();
    return window;
}

pub fn Deinit(self: *Window) void {
    self._Impl.Deinit();
    self._EngineAllocator.destroy(self);
}

pub fn GetWidth(self: Window) usize {
    return self._Impl.GetWidth();
}

pub fn GetHeight(self: Window) usize {
    return self._Impl.GetHeight();
}

pub fn SetVSync(self: *Window, useVSync: bool) void {
    self._Impl.SetVSync(useVSync);
}

pub fn IsVSync(self: Window) bool {
    return self._Impl.IsVSync();
}

pub fn GetNativeWindow(self: Window) *void {
    return self._Impl.GetNativeWindow();
}

pub fn OnWindowResize(self: *Window, width: usize, height: usize) void {
    self._Impl.OnWindowResize(width, height);
}

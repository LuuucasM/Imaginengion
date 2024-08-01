const std = @import("std");
const builtin = @import("builtin");
const Window = @This();

const WindowsWindow = @import("WindowsWindow.zig");
const UnsupportedWindow = @import("UnsupportedWindow.zig");

const Impl = switch (builtin.os.tag) {
    .windows => WindowsWindow,
    else => UnsupportedWindow,
};

_Impl: Impl,

pub fn init(EngineAllocator: std.mem.Allocator) !Window {
    const window = try EngineAllocator.create(Window);
    window = .{ ._Impl = .{} };
    window._Impl.init();
    return window;
}

pub fn deinit(self: *Window) void {
    self.*._Impl.deinit();
}

pub fn GetWidth(self: *Window) usize {
    self.*._Impl.GetWidth();
}

pub fn GetHeight(self: *Window) usize {
    self.*._Impl.GetHeight();
}

pub fn SetVSync(self: *Window, useVSync: bool) void {
    self.*._Impl.SetVSync(useVSync);
}

pub fn IsVSync(self: *Window) bool {
    return self.*._Impl.IsVSync();
}

pub fn GetNativeWindow(self: *Window) *void {
    return self.*._Impl.IsVSync();
}

pub fn OnWindowResize(self: *Window, width: usize, height: usize) void {
    return self.*._Impl.OnWindowResize(width, height);
}

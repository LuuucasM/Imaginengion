const std = @import("std");
const builtin = @import("builtin");
const EngineContext = @import("../Core/EngineContext.zig");
const Window = @This();

const Impl = switch (builtin.os.tag) {
    .windows => @import("SDLWindow.zig"),
    else => @import("UnsupportedWindow.zig"),
};

_Impl: Impl = .{},

pub fn Init(self: *Window, engine_context: *EngineContext) void {
    self._Impl.Init(engine_context);
}

pub fn Deinit(self: *Window) void {
    self._Impl.Deinit();
}

pub fn GetWidth(self: Window) usize {
    return self._Impl.GetWidth();
}

pub fn GetHeight(self: Window) usize {
    return self._Impl.GetHeight();
}

pub fn GetNativeWindow(self: Window) *anyopaque {
    return self._Impl.GetNativeWindow();
}

pub fn PollInputEvents(self: *Window, engine_context: *EngineContext) !void {
    try self._Impl.PollInputEvents(engine_context);
}

pub fn IsMinimized(self: Window) bool {
    return self._Impl.IsMinimized();
}

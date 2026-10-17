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

/// Sets the title bar / taskbar icon from a PNG's bytes
pub fn SetIcon(self: Window, png_bytes: []const u8) !void {
    try self._Impl.SetIcon(png_bytes);
}

/// Sets the text in the title bar. `allocator` is only used for the copy handed to the OS
pub fn SetTitle(self: Window, allocator: std.mem.Allocator, title: []const u8) !void {
    try self._Impl.SetTitle(allocator, title);
}

pub fn PollInputEvents(self: *Window, engine_context: *EngineContext) !void {
    try self._Impl.PollInputEvents(engine_context);
}

/// Turns typed text (TextTyped events) on and off: on while something is being typed into
pub fn StartTextInput(self: Window) void {
    self._Impl.StartTextInput();
}

pub fn StopTextInput(self: Window) void {
    self._Impl.StopTextInput();
}

/// A copy of the clipboard's text, empty if there is none. The caller frees it
pub fn GetClipboardText(self: Window, allocator: std.mem.Allocator) ![]u8 {
    return self._Impl.GetClipboardText(allocator);
}

/// Puts `text` on the clipboard. `allocator` is only used for the copy handed to the OS
pub fn SetClipboardText(self: Window, allocator: std.mem.Allocator, text: []const u8) !void {
    return self._Impl.SetClipboardText(allocator, text);
}

pub fn IsMinimized(self: Window) bool {
    return self._Impl.IsMinimized();
}

pub fn GetPixelDensity(self: Window) f32 {
    return self._Impl.GetPixelDensity();
}

pub fn GetDisplayScale(self: Window) f32 {
    return self._Impl.GetDisplayScale();
}

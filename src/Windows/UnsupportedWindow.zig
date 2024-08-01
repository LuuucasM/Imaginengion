const UnsupportedWindow = @This();

pub fn init(self: *UnsupportedWindow) void {}

pub fn deinit(self: *UnsupportedWindow) void {}

pub fn GetWidth(self: *UnsupportedWindow) usize {}

pub fn GetHeight(self: *UnsupportedWindow) usize {}

pub fn SetVSync(self: *UnsupportedWindow) void {}

pub fn IsVSync(self: *UnsupportedWindow) bool {}

pub fn GetNativeWindow(self: *UnsupportedWindow) *void {}

pub fn OnWindowResize(self: *UnsupportedWindow) void {}

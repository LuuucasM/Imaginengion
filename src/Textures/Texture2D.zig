const builtin = @import("builtin");
const Texture2D = @This();

const Impl = switch (builtin.os.tag) {
    .windows => @import("OpenGLTexture2D.zig"),
    else => @import("UnsupportedTexture2D.zig"),
};

_Impl: Impl = .{},

pub fn InitData(self: *Texture2D, width: u32, height: u32, channels: u32, data: *anyopaque, size: usize) void {
    self._Impl.InitData(width, height, channels, data, size);
}

pub fn InitPath(self: *Texture2D, path: []const u8) void {
    self._Impl.InitPath(path);
}

pub fn Deinit(self: Texture2D) void {
    self._Impl.Deinit();
}

pub fn GetWidth(self: Texture2D) u32 {
    return self._Impl.GetWidth();
}
pub fn GetHeight(self: Texture2D) u32 {
    return self._Impl.GetHeight();
}
pub fn GetID(self: Texture2D) u32 {
    return self._Impl.GetID();
}
pub fn UpdateData(self: *Texture2D, data: *anyopaque, size: usize) void {
    self._Impl.UpdateData(data, size);
}
pub fn UpdateDataPath(self: *Texture2D, path: []const u8) void {
    self._Impl.UpdateDataPath(path);
}
pub fn Bind(self: Texture2D, slot: u32) void {
    self._Impl.Bind(slot);
}
pub fn Unbind(self: Texture2D, slot: u32) void {
    self._Impl.Unbind(slot);
}

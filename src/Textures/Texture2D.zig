const builtin = @import("builtin");
const Texture2D = @This();

const Impl = switch (builtin.os.tag) {
    .windows => @import("OpenGLTexture2D.zig"),
    else => @import("UnsupportedTexture2D.zig"),
};

_Impl: Impl = .{},

pub fn InitSize(self: Texture2D, width: u32, height: u32) void {
    self._Impl.InitSize(width, height);
}

pub fn InitPath(self: Texture2D, path: []const u8) void {
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
pub fn SetData(self: Texture2D, data: *anyopaque) void {
    self._Impl.SetData(data);
}
pub fn Bind(self: Texture2D) void {
    self._Impl.Bind();
}
pub fn Unbind(self: Texture2D) void {
    self._Impl.Unbind();
}

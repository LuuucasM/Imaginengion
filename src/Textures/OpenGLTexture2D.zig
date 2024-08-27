const glad = @import("../Core/CImports.zig").glad;
const OpenGLTexture2D = @This();

pub fn InitSize(self: OpenGLTexture2D, width: u32, height: u32) void {}

pub fn InitPath(self: OpenGLTexture2D, path: []const u8) void {}

pub fn Deinit(self: OpenGLTexture2D) void {}
pub fn GetWidth(self: OpenGLTexture2D) u32 {}
pub fn GetHeight(self: OpenGLTexture2D) u32 {}
pub fn GetID(self: OpenGLTexture2D) u32 {}
pub fn SetData(self: OpenGLTexture2D, data: *anyopaque) void {}
pub fn Unbind(self: OpenGLTexture2D) void {}

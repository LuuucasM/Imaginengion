const std = @import("std");
const glad = @import("../Core/CImports.zig").glad;
const stb = @import("../Core/CImports.zig").stb;
const OpenGLTexture2D = @This();

_Width: c_int = 0,
_Height: c_int = 0,
_TextureID: c_uint = 0,
_InternalFormat: c_uint = glad.GL_RGBA8,
_DataFormat: c_uint = glad.GL_RGBA,

pub fn InitData(self: *OpenGLTexture2D, width: u32, height: u32, channels: u32, data: *anyopaque, size: usize) void {
    _ = size;
    self._Width = @intCast(width);
    self._Height = @intCast(height);
    if (channels == 4) {
        self._InternalFormat = glad.GL_RGBA8;
        self._DataFormat = glad.GL_RGBA;
    } else if (channels == 3) {
        self._InternalFormat = glad.GL_RGB8;
        self._DataFormat = glad.GL_RGB;
    } else {
        std.log.err("Textureformat not supported in OpenGLTexture2D when loading loading data", .{});
        @panic("");
    }
    glad.glCreateTextures(glad.GL_TEXTURE_2D, 1, &self._TextureID);
    glad.glTextureStorage2D(self._TextureID, 1, self._InternalFormat, self._Width, self._Height);

    glad.glTextureParameteri(self._TextureID, glad.GL_TEXTURE_MIN_FILTER, glad.GL_LINEAR);
    glad.glTextureParameteri(self._TextureID, glad.GL_TEXTURE_MAG_FILTER, glad.GL_NEAREST);

    glad.glTextureParameteri(self._TextureID, glad.GL_TEXTURE_WRAP_S, glad.GL_REPEAT);
    glad.glTextureParameteri(self._TextureID, glad.GL_TEXTURE_WRAP_T, glad.GL_REPEAT);
    glad.glTextureSubImage2D(self._TextureID, 0, 0, 0, self._Width, self._Height, self._DataFormat, glad.GL_UNSIGNED_BYTE, data);
}

pub fn InitPath(self: *OpenGLTexture2D, path: []const u8) !void {
    var width: c_int = 0;
    var height: c_int = 0;
    var channels: c_int = 0;
    var data: ?*stb.stbi_uc = null;
    stb.stbi_set_flip_vertically_on_load(1);

    var file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();
    const fstats = try file.stat();

    const contents = try file.readToEndAlloc(std.heap.page_allocator, @intCast(fstats.size));
    defer std.heap.page_allocator.free(contents);

    data = stb.stbi_load_from_memory(contents.ptr, @intCast(contents.len), &width, &height, &channels, 0);
    defer stb.stbi_image_free(data);
    std.debug.assert(data != null);

    self._Width = width;
    self._Height = height;
    if (channels == 4) {
        self._InternalFormat = glad.GL_RGBA8;
        self._DataFormat = glad.GL_RGBA;
    } else if (channels == 3) {
        self._InternalFormat = glad.GL_RGB8;
        self._DataFormat = glad.GL_RGB;
    } else {
        std.log.err("Textureformat not supported in OpenGLTexture2D when loading file: {s}", .{path});
        @panic("");
    }

    glad.glCreateTextures(glad.GL_TEXTURE_2D, 1, &self._TextureID);
    glad.glTextureStorage2D(self._TextureID, 1, self._InternalFormat, self._Width, self._Height);

    glad.glTextureParameteri(self._TextureID, glad.GL_TEXTURE_MIN_FILTER, glad.GL_LINEAR);
    glad.glTextureParameteri(self._TextureID, glad.GL_TEXTURE_MAG_FILTER, glad.GL_NEAREST);

    glad.glTextureParameteri(self._TextureID, glad.GL_TEXTURE_WRAP_S, glad.GL_REPEAT);
    glad.glTextureParameteri(self._TextureID, glad.GL_TEXTURE_WRAP_T, glad.GL_REPEAT);

    glad.glTextureSubImage2D(self._TextureID, 0, 0, 0, self._Width, self._Height, self._DataFormat, glad.GL_UNSIGNED_BYTE, data);
}

pub fn Deinit(self: OpenGLTexture2D) void {
    glad.glDeleteTextures(1, &self._TextureID);
}
pub fn GetWidth(self: OpenGLTexture2D) u32 {
    return self._Width;
}
pub fn GetHeight(self: OpenGLTexture2D) u32 {
    return self._Height;
}
pub fn GetID(self: OpenGLTexture2D) u32 {
    return self._TextureID;
}
pub fn UpdateData(self: *OpenGLTexture2D, width: u32, height: u32, data: *anyopaque, size: usize) void {
    _ = size;
    self._Width = width;
    self._Height = height;
    glad.glTextureSubImage2D(self._TextureID, 0, 0, 0, self._Width, self._Height, self._DataFormat, glad.GL_UNSIGNED_BYTE, data);
}
pub fn UpdateDataPath(self: *OpenGLTexture2D, path: []const u8) void {
    var width: c_int = 0;
    var height: c_int = 0;
    var channels: c_int = 0;
    var data: ?*stb.stbi_uc = null;
    stb.stbi_set_flip_vertically_on_load(1);

    data = stb.stbi_load(@ptrCast(path), &width, &height, &channels, 0);
    defer stb.stbi_image_free(data);
    std.debug.assert(data != null);

    self._Width = width;
    self._Height = height;
    glad.glTextureSubImage2D(self._TextureID, 0, 0, 0, self._Width, self._Height, self._DataFormat, glad.GL_UNSIGNED_BYTE, data);
}
pub fn Bind(self: OpenGLTexture2D, slot: u32) void {
    glad.glBindTextureUnit(slot, self._TextureID);
}
pub fn Unbind(self: OpenGLTexture2D, slot: u32) void {
    _ = self;
    _ = slot;
    glad.glBindTexture(glad.GL_TEXTURE_2D, 0);
}

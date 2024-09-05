const std = @import("std");
const glad = @import("../Core/CImports.zig").glad;
const stb = @import("../Core/CImports.zig").stb;
const OpenGLTexture2D = @This();

_Width: u32 = 0,
_Height: u32 = 0,
_TextureID: u32 = 0,
var _InternalFormat: u32 = glad.GL_RGBA8;
var _DataFormat: u32 = glad.GL_RGBA;

pub fn InitSize(self: OpenGLTexture2D, width: u32, height: u32) void {

    self._Width = width;
    self._Height = height;
    glad.glCreateTextures(glad.GL_TEXTURE_2D, 1, &self._TextureID);
    glad.glTextureStorage(self._TextureID, 1, internalFormat, self._Width, self._Height);

    glad.glTextureParameteri(self._TextureID, glad.GL_TEXTURE_MIN_FILTER, glad.GL_LINEAR);
    glad.glTextureParameteri(self._TextureID, glad.GL_TEXTURE_MAG_FILTER, glad.GL_NEAREST);

    glad.glTextureParameteri(self._TextureID, glad.GL_TEXTURE_WRAP_S, glad.GL_REPEAT);
    glad.glTextureParameteri(self._TextureID, glad.GL_TEXTURE_WRAP_T, glad.GL_REPEAT);
}

pub fn InitPath(self: OpenGLTexture2D, path: []const u8) void {
    var width: u32 = 0;
    var height: u32 = 0;
    var channels: u32 = 0;
    var data: ?*stb.struct_stbi_uc = null;
    stb.stbi_set_flip_vertically_on_load(1);

    data = stb.stbi_load(path, &width, &height, &channels, 0);
    defer stb.stbi_image_free(data);
    std.debug.assert(data != null);

    self._Width = width;
    self._Height = height;

    if (channels == 4){
        self._internalFormat = glad.GL_RGBA8;
        self._DataFormat = glad.GL_RGBA;
    }
    else if (channels == 3){
        self._internalFormat = glad.GL_RGB8;
        self._DataFormat = glad.GL_RGB;
    }
    else{
        std.debug.error("Textureformat not supported in OpenGLTexture2D when loading file: {s}", path);
        @panic("");
    }

    glad.glCreateTextures(glad.GL_TEXTURE_2D, 1, &self._TextureID);
    glad.glTextureStorage(self._TextureID, 1, internalFormat, self._Width, self._Height);

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
pub fn SetData(self: OpenGLTexture2D, data: *anyopaque, size: usize) void {
    glad.glTextureSubImage2D(self._TextureID, 0, 0, 0, self._Width, self._Height, self._DataFormat, glad.GL_UNSIGNED_BYTE, data);
}
pub fn SetDataFromPath(self: OpenGLTexture2D, path: []const u8) void {
    var width: u32 = 0;
    var height: u32 = 0;
    var channels: u32 = 0;
    var data: ?*stb.struct_stbi_uc = null;
    stb.stbi_set_flip_vertically_on_load(1);

    data = stb.stbi_load(path, &width, &height, &channels, 0);
    defer stb.stbi_image_free(data);
    std.debug.assert(data != null);

    self._Width = width;
    self._Height = height;

    if (channels == 4){
        self._internalFormat = glad.GL_RGBA8;
        self._DataFormat = glad.GL_RGBA;
    }
    else if (channels == 3){
        self._internalFormat = glad.GL_RGB8;
        self._DataFormat = glad.GL_RGB;
    }
    else{
        std.debug.error("Textureformat not supported in OpenGLTexture2D when loading file: {s}", path);
        @panic("");
    }

    glad.glTextureStorage(self._TextureID, 1, internalFormat, self._Width, self._Height);

    glad.glTextureSubImage2D(self._TextureID, 0, 0, 0, self._Width, self._Height, self._DataFormat, glad.GL_UNSIGNED_BYTE, data);
}
pub fn Bind(self: OpenGLTexture2D, slot: u32) void {
    glad.glBindTextureUnit(slot, self._TextureID);
}
pub fn Unbind(self: OpenGLTexture2D, slot: u32) void {
    glad.glBindTexture(GL_TEXTURE_2D, 0);
}
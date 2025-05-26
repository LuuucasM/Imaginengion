const std = @import("std");
const glad = @import("../../../Core/CImports.zig").glad;
const stb = @import("../../../Core/CImports.zig").stb;
const OpenGLTexture2D = @This();

_Width: c_int,
_Height: c_int,
_TextureID: c_uint,
_InternalFormat: c_uint,
_DataFormat: c_uint,
mSlot: usize,

pub fn Init(allocator: std.mem.Allocator, abs_path: []const u8) !OpenGLTexture2D {
    _ = allocator;
    var width: c_int = 0;
    var height: c_int = 0;
    var channels: c_int = 0;
    var data: ?*stb.stbi_uc = null;
    stb.stbi_set_flip_vertically_on_load(1);

    var file = try std.fs.cwd().openFile(abs_path, .{});
    defer file.close();
    const fstats = try file.stat();

    const contents = try file.readToEndAlloc(std.heap.page_allocator, @intCast(fstats.size));
    defer std.heap.page_allocator.free(contents);

    data = stb.stbi_load_from_memory(contents.ptr, @intCast(contents.len), &width, &height, &channels, 0);
    defer stb.stbi_image_free(data);
    std.debug.assert(data != null);

    var internal_format: c_uint = 0;
    var data_format: c_uint = 0;
    if (channels == 4) {
        internal_format = glad.GL_RGBA8;
        data_format = glad.GL_RGBA;
    } else if (channels == 3) {
        internal_format = glad.GL_RGB8;
        data_format = glad.GL_RGB;
    } else {
        std.log.err("Textureformat not supported in OpenGLTexture2D when loading file: {s}", .{abs_path});
        @panic("");
    }

    var new_texture_id: c_uint = 0;
    glad.glCreateTextures(glad.GL_TEXTURE_2D, 1, &new_texture_id);

    glad.glTextureParameteri(new_texture_id, glad.GL_TEXTURE_BASE_LEVEL, 0);
    glad.glTextureParameteri(new_texture_id, glad.GL_TEXTURE_MAX_LEVEL, 0);
    glad.glTextureParameteri(new_texture_id, glad.GL_TEXTURE_MIN_FILTER, glad.GL_LINEAR);
    glad.glTextureParameteri(new_texture_id, glad.GL_TEXTURE_MAG_FILTER, glad.GL_LINEAR);
    glad.glTextureParameteri(new_texture_id, glad.GL_TEXTURE_WRAP_S, glad.GL_REPEAT);
    glad.glTextureParameteri(new_texture_id, glad.GL_TEXTURE_WRAP_T, glad.GL_REPEAT);
    glad.glTextureStorage2D(new_texture_id, 1, internal_format, width, height);

    glad.glTextureSubImage2D(new_texture_id, 0, 0, 0, width, height, data_format, glad.GL_UNSIGNED_BYTE, data);

    return OpenGLTexture2D{
        ._Width = width,
        ._Height = height,
        ._TextureID = new_texture_id,
        ._InternalFormat = internal_format,
        ._DataFormat = data_format,
        .mSlot = std.math.maxInt(usize),
    };
}

pub fn Deinit(self: OpenGLTexture2D) !void {
    glad.glDeleteTextures(1, &self._TextureID);
}
pub fn GetWidth(self: OpenGLTexture2D) usize {
    return self._Width;
}
pub fn GetHeight(self: OpenGLTexture2D) usize {
    return self._Height;
}
pub fn GetID(self: OpenGLTexture2D) c_uint {
    return self._TextureID;
}

pub fn UpdateDataPath(self: *OpenGLTexture2D, path: []const u8) !void {
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
    glad.glTextureSubImage2D(self._TextureID, 0, 0, 0, self._Width, self._Height, self._DataFormat, glad.GL_UNSIGNED_BYTE, data);
}
pub fn Bind(self: *OpenGLTexture2D, slot: usize) void {
    glad.glBindTextureUnit(@intCast(slot), self._TextureID);
    self.mSlot = @intCast(slot);
}
pub fn Unbind(self: *OpenGLTexture2D) void {
    glad.glBindTextureUnit(self.mSlot, 0);
    self.mSlot = std.math.maxInt(usize);
}

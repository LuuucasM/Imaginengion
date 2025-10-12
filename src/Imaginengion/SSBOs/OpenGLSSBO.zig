const glad = @import("../Core/CImports.zig").glad;
const OpenGLSSBO = @This();

mSize: usize,
mBindIndex: c_uint,
mBufferID: c_uint,

pub fn Init(size: usize) OpenGLSSBO {
    var new_ssbo = OpenGLSSBO{
        .mSize = size,
        .mBufferID = undefined,
        .mBindIndex = 0,
    };
    glad.glCreateBuffers(1, @ptrCast(&new_ssbo.mBufferID));
    glad.glNamedBufferData(new_ssbo.mBufferID, @intCast(size), null, glad.GL_DYNAMIC_DRAW);

    glad.glObjectLabel(glad.GL_BUFFER, new_ssbo.mBufferID, -1, "SSBO");

    return new_ssbo;
}

pub fn Deinit(self: OpenGLSSBO) void {
    glad.glDeleteBuffers(1, &self.mBufferID);
}

pub fn Bind(self: *OpenGLSSBO, binding: usize) void {
    self.mBindIndex = @intCast(binding);
    glad.glBindBufferBase(glad.GL_SHADER_STORAGE_BUFFER, self.mBindIndex, self.mBufferID);
}

pub fn Unbind(self: OpenGLSSBO) void {
    glad.glBindBufferBase(glad.GL_SHADER_STORAGE_BUFFER, self.mBindIndex, 0);
}

pub fn SetData(self: OpenGLSSBO, data: *anyopaque, size: usize, offset: u32) void {
    if (size > self.mSize) {
        glad.glNamedBufferData(self.mBufferID, @intCast(size), data, glad.GL_DYNAMIC_COPY);
    } else {
        glad.glNamedBufferSubData(self.mBufferID, offset, @intCast(size), data);
    }
}

const glad = @import("../Core/CImports.zig").glad;
const OpenGLSSBO = @This();

mSize: usize,
mBindIndex: c_uint,
mBufferID: c_uint,

pub fn Init(size: usize) OpenGLSSBO {
    const new_ssbo = OpenGLSSBO{
        .mSize = size,
        .mBufferID = undefined,
    };
    glad.glCreateBuffers(1, &new_ssbo.mBufferID);
    glad.glNamedBufferData(new_ssbo.mBufferID, size, null, glad.GL_DYNAMIC_DRAW);
}

pub fn Deinit(self: OpenGLSSBO) void {
    glad.glDeleteBuffers(1, &self.mBufferID);
}

pub fn Bind(self: OpenGLSSBO, binding: usize) void {
    self.mBindIndex = @intCast(binding);
    glad.glBindBufferBase(glad.GL_UNIFORM_BUFFER, self.mBindIndex, self.mBufferID);
}

pub fn Unbind(self: OpenGLSSBO) void {
    glad.glBindBufferBase(glad.GL_UNIFORM_BUFFER, self.mBindIndex, 0);
}

pub fn SetData(self: OpenGLSSBO, data: *anyopaque, size: usize, offset: u32) void {
    if (size > self.mSize) {
        glad.glNamedBufferData(self.mBufferID, size, data, glad.GL_DYNAMIC_COPY);
    } else {
        glad.glNamedBufferSubData(self.mBufferID, offset, size, data);
    }
}

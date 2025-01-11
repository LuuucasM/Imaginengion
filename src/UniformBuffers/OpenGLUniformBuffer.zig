const glad = @import("../Core/CImports.zig").glad;
const OpenGLUniformBuffer = @This();

mBufferID: u32,

pub fn Init(size: u32, binding: u32) OpenGLUniformBuffer {
    const new_ub = OpenGLUniformBuffer{
        .mBufferID = undefined,
    };
    glad.glCreateBuffers(1, &new_ub.mBufferID);
    glad.glNamedBufferData(new_ub.mBufferID, size, null, glad.GL_DYNAMIC_DRAW);
    glad.glBindBufferBase(glad.GL_UNIFORM_BUFFER, binding, new_ub.mBufferID);
}

pub fn Deinit(self: OpenGLUniformBuffer) void {
    glad.glDeleteBuffers(1, &self.mBufferID);
}

pub fn SetData(self: OpenGLUniformBuffer, data: *anyopaque, size: u32, offset: u32) void {
    glad.glNamedBufferSubData(self.mBufferID, offset, size, data);
}

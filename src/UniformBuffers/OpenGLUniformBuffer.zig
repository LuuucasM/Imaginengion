const glad = @import("../Core/CImports.zig").glad;
const OpenGLUniformBuffer = @This();

mBufferID: c_uint,

pub fn Init(size: u32) OpenGLUniformBuffer {
    var new_ub = OpenGLUniformBuffer{
        .mBufferID = undefined,
    };
    glad.glCreateBuffers(1, &new_ub.mBufferID);
    glad.glNamedBufferData(new_ub.mBufferID, size, null, glad.GL_DYNAMIC_DRAW);

    return new_ub;
}

pub fn Bind(self: OpenGLUniformBuffer, binding: usize) void {
    glad.glBindBufferBase(glad.GL_UNIFORM_BUFFER, @intCast(binding), self.mBufferID);
}

pub fn Deinit(self: OpenGLUniformBuffer) void {
    glad.glDeleteBuffers(1, &self.mBufferID);
}

pub fn SetData(self: OpenGLUniformBuffer, data: *anyopaque, size: u32, offset: u32) void {
    glad.glNamedBufferSubData(self.mBufferID, offset, size, data);
}

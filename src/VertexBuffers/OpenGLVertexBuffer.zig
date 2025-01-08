const glad = @import("../Core/CImports.zig").glad;

const OpenGLVertexBuffer = @This();

pub fn Init(size: usize, buffer_id_out: *c_uint) void {
    glad.glCreateBuffers(1, buffer_id_out);
    glad.glBindBuffer(glad.GL_ARRAY_BUFFER, buffer_id_out.*);
    glad.glBufferData(glad.GL_ARRAY_BUFFER, size, null, glad.GL_DYNAMIC_DRAW);
}

pub fn Deinit(buffer_id_out: c_uint) void {
    glad.glDeleteBuffers(1, buffer_id_out);
}

pub fn Bind(buffer_id_out: c_uint) void {
    glad.glBindBuffer(glad.GL_ARRAY_BUFFER, buffer_id_out);
}

pub fn Unbind() void {
    glad.glBindBuffer(glad.GL_ARRAY_BUFFER, 0);
}

pub fn SetData(buffer_id_out: c_uint, data: *anyopaque, size: usize) void {
    glad.glBindBuffer(glad.GL_ARRAY_BUFFER, buffer_id_out);
    glad.BufferSubData(glad.GL_ARRAY_BUFFER, 0, size, data);
}

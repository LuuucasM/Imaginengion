const glad = @import("../Core/CImports.zig").glad;

const OpenGLIndexBuffer = @This();

pub fn Init(buffer_id_out: *c_uint, indices: []u32, count: u32) void {
    glad.glCreateBuffers(1, buffer_id_out);
    glad.glBindBuffer(glad.GL_ARRAY_BUFFER, buffer_id_out.*);
    glad.glBufferData(glad.GL_ARRAY_BUFFER, count * @sizeOf(u32), indices, glad.GL_STATIC_DRAW);
}

pub fn Bind(buffer_id: c_uint) void {
    glad.glBindBuffer(glad.GL_ELEMENT_ARRAY_BUFFER, buffer_id);
}

pub fn Unbind() void {
    glad.glBindBuffer(glad.GL_ELEMENT_ARRAY_BUFFER, 0);
}

pub fn Deinit(buffer_id_out: *c_uint) void {
    glad.glDeleteBuffers(1, buffer_id_out);
}

const glad = @import("../Core/CImports.zig").glad;

const OpenGLIndexBuffer = @This();

mCount: usize,
mBufferID: c_uint,

pub fn Init(indices: []u32, count: usize) OpenGLIndexBuffer {
    var new_ib = OpenGLIndexBuffer{
        .mCount = count,
        .mBufferID = undefined,
    };

    glad.glCreateBuffers(1, &new_ib.mBufferID);
    glad.glBindBuffer(glad.GL_ARRAY_BUFFER, new_ib.mBufferID);
    glad.glBufferData(glad.GL_ARRAY_BUFFER, @intCast(count * @sizeOf(u32)), indices.ptr, glad.GL_STATIC_DRAW);

    return new_ib;
}

pub fn Deinit(self: OpenGLIndexBuffer) void {
    glad.glDeleteBuffers(1, self.mBufferID);
}

pub fn Bind(self: OpenGLIndexBuffer) void {
    glad.glBindBuffer(glad.GL_ELEMENT_ARRAY_BUFFER, self.mBufferID);
}

pub fn Unbind(self: OpenGLIndexBuffer) void {
    _ = self;
    glad.glBindBuffer(glad.GL_ELEMENT_ARRAY_BUFFER, 0);
}

pub fn GetCount(self: OpenGLIndexBuffer) usize {
    return self.mCount;
}

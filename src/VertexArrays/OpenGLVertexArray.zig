const std = @import("std");

const VertexBuffer = @import("../VertexBuffers/VertexBuffer.zig");
const IndexBuffer = @import("../IndexBuffers/IndexBuffer.zig");

const OpenGLVertexArray = @This();

mArrayID: c_uint,
mVertexBuffers: std.ArrayList(VertexBuffer),
mIndexBuffer: IndexBuffer,

pub fn Init() OpenGLVertexArray {
    return OpenGLVertexArray{
        .mArrayID = 0,
        .mVertexBuffers = std.ArrayList(VertexBuffer).init(),
        .mIndexBuffer = 0,
    };
}

pub fn Deinit(self: OpenGLVertexArray) void {
    self.mImpl.Deinit();
}

pub fn Bind(self: OpenGLVertexArray) void {
    self.mImpl.Bind();
}

pub fn Unbind(self: OpenGLVertexArray) void {
    self.mImpl.Unbind();
}

pub fn AddVertexBuffer(self: OpenGLVertexArray, vertex_buffer: VertexBuffer) void {
    self.mImpl.AddVertexBuffer(vertex_buffer);
}

pub fn SetIndexBuffer(self: OpenGLVertexArray, index_buffer: IndexBuffer) void {
    self.mImpl.SetIndexBuffer(index_buffer);
}

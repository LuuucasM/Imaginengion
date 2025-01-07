const std = @import("std");
const builtin = @import("builtin");

const VertexBuffer = @import("../VertexBuffers/VertexBuffer.zig");
const IndexBuffer = @import("../IndexBuffers/IndexBuffer.zig");

const Impl = switch (builtin.os.tag) {
    .windows => @import("OpenGLVertexArray.zig"),
    else => @import("UnsupportedVertexArray.zig"),
};

const VertexArray = @This();

mImpl: Impl,
mArrayID: c_uint,
mVertexBuffers: std.ArrayList(VertexBuffer),
mIndexBuffer: IndexBuffer,

pub fn Init() VertexArray {
    return VertexArray{
        .mImpl = Impl.Init(),
        .mArrayID = 0,
        .mVertexBuffers = std.ArrayList(VertexBuffer).init(),
        .mIndexBuffer = 0,
    };
}

pub fn Deinit(self: VertexArray) void {
    self.mImpl.Deinit();
}

pub fn Bind(self: VertexArray) void {
    self.mImpl.Bind();
}

pub fn Unbind(self: VertexArray) void {
    self.mImpl.Unbind();
}

pub fn AddVertexBuffer(self: VertexArray, new_vertex_buffer: VertexBuffer) void {
    self.mImpl.AddVertexBuffer(new_vertex_buffer);
    self.mVertexBuffers.append(new_vertex_buffer);
}

pub fn SetIndexBuffer(self: VertexArray, new_index_buffer: IndexBuffer) void {
    self.mImpl.SetIndexBuffer(new_index_buffer);
    self.mIndexBuffer = new_index_buffer;
}

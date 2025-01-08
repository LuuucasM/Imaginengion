const std = @import("std");
const builtin = @import("builtin");

const VertexBuffer = @import("../VertexBuffers/VertexBuffer.zig");
const IndexBuffer = @import("../IndexBuffers/IndexBuffer.zig");

const Impl = switch (builtin.os.tag) {
    .windows => @import("OpenGLVertexArray.zig"),
    else => @import("UnsupportedVertexArray.zig"),
};

const VertexArray = @This();

mArrayID: c_uint,
mVertexBuffers: std.ArrayList(VertexBuffer),
mIndexBuffer: IndexBuffer,

pub fn Init() VertexArray {
    const new_va = VertexArray{
        .mArrayID = 0,
        .mVertexBuffers = std.ArrayList(VertexBuffer).init(),
        .mIndexBuffer = 0,
    };
    Impl.Init(&new_va.mArrayID);
    return new_va;
}

pub fn Deinit(self: VertexArray) void {
    Impl.Deinit(&self.mArrayID);
}

pub fn Bind(self: VertexArray) void {
    Impl.Bind(self.mArrayID);
}

pub fn Unbind(self: VertexArray) void {
    _ = self;
    Impl.Unbind();
}

pub fn AddVertexBuffer(self: VertexArray, new_vertex_buffer: VertexBuffer) void {
    self.Bind();
    self.mImpl.AddVertexBuffer(new_vertex_buffer);
    self.mVertexBuffers.append(new_vertex_buffer);
}

pub fn SetIndexBuffer(self: VertexArray, new_index_buffer: IndexBuffer) void {
    self.Bind();
    self.mImpl.SetIndexBuffer(new_index_buffer);
    self.mIndexBuffer = new_index_buffer;
}

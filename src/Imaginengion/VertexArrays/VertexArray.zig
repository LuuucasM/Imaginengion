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

pub fn Init() VertexArray {
    return VertexArray{
        .mImpl = Impl.Init(),
    };
}

pub fn Deinit(self: *VertexArray, engine_allocator: std.mem.Allocator) void {
    self.mImpl.Deinit(engine_allocator);
}

pub fn Bind(self: VertexArray) void {
    self.mImpl.Bind();
}

pub fn Unbind(self: VertexArray) void {
    self.mImpl.Unbind();
}

pub fn AddVertexBuffer(self: *VertexArray, engine_allocator: std.mem.Allocator, new_vertex_buffer: VertexBuffer) !void {
    try self.mImpl.AddVertexBuffer(engine_allocator, new_vertex_buffer);
}

pub fn SetIndexBuffer(self: *VertexArray, new_index_buffer: IndexBuffer) void {
    self.mImpl.SetIndexBuffer(new_index_buffer);
}

pub fn GetIndexBuffer(self: VertexArray) IndexBuffer {
    return self.mImpl.GetIndexBuffer();
}

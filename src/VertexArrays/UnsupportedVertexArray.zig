const std = @import("std");

const VertexBuffer = @import("../VertexBuffers/VertexBuffer.zig");
const IndexBuffer = @import("../IndexBuffers/IndexBuffer.zig");

const UnsupportedVertexArray = @This();

pub fn Init() UnsupportedVertexArray {
    Unsupported();
    return UnsupportedVertexArray{};
}

pub fn Deinit(self: UnsupportedVertexArray) void {
    _ = self;
    Unsupported();
}

pub fn Bind(self: UnsupportedVertexArray) void {
    _ = self;
    Unsupported();
}

pub fn Unbind(self: UnsupportedVertexArray) void {
    _ = self;
    Unsupported();
}

pub fn AddVertexBuffer(self: UnsupportedVertexArray, vertex_buffer: VertexBuffer) void {
    _ = self;
    _ = vertex_buffer;
    Unsupported();
}

pub fn SetIndexBuffer(self: UnsupportedVertexArray, index_buffer: IndexBuffer) void {
    _ = self;
    _ = index_buffer;
    Unsupported();
}

fn Unsupported() noreturn {
    @compileError("Unsupported OS for RenderContext");
}

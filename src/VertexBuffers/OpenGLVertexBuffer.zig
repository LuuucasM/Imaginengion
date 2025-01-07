const std = @import("std");

const OpenGLVertexBuffer = @This();

pub fn Init(size: usize) OpenGLVertexBuffer {
    _ = size;
    return OpenGLVertexBuffer{};
}

pub fn Deinit(self: OpenGLVertexBuffer) void {
    _ = self;
}

pub fn Bind(self: OpenGLVertexBuffer) void {
    _ = self;
}

pub fn Unbind(self: OpenGLVertexBuffer) void {
    _ = self;
}

pub fn SetData(self: OpenGLVertexBuffer, data: *anyopaque, size: usize) void {
    _ = self;
    _ = data;
    _ = size;
}

const std = @import("std");
const VertexBufferElement = @import("VertexBufferElement.zig");

const UnsupportedVertexBuffer = @This();

pub fn Init(allocator: std.mem.Allocator, size: usize) UnsupportedVertexBuffer {
    _ = allocator;
    _ = size;
    Unsupported();
    return UnsupportedVertexBuffer{};
}

pub fn Deinit(self: UnsupportedVertexBuffer) void {
    _ = self;
    Unsupported();
}

pub fn Bind(self: UnsupportedVertexBuffer) void {
    _ = self;
    Unsupported();
}

pub fn Unbind() void {
    Unsupported();
}

pub fn SetData(self: UnsupportedVertexBuffer, data: *anyopaque, size: usize) void {
    _ = self;
    _ = data;
    _ = size;
    Unsupported();
}

pub fn SetLayout(self: UnsupportedVertexBuffer, layout: std.ArrayList(VertexBufferElement)) void {
    _ = self;
    _ = layout;
    Unsupported();
}

pub fn SetStride(self: UnsupportedVertexBuffer, stride: u32) void {
    _ = self;
    _ = stride;
    Unsupported();
}

pub fn GetLayout(self: UnsupportedVertexBuffer) std.ArrayList(VertexBufferElement) {
    _ = self;
    Unsupported();
}

pub fn GetStride(self: UnsupportedVertexBuffer) u32 {
    _ = self;
    Unsupported();
}

fn Unsupported() noreturn {
    @compileError("Unsupported OS for RenderContext");
}

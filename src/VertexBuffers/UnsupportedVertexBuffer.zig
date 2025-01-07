const std = @import("std");

const UnsupportedVertexBuffer = @This();

pub fn Init(size: usize) UnsupportedVertexBuffer {
    _ = size;
    return UnsupportedVertexBuffer{};
}

pub fn Deinit(self: UnsupportedVertexBuffer) void {
    _ = self;
}

pub fn Bind(self: UnsupportedVertexBuffer) void {
    _ = self;
}

pub fn Unbind(self: UnsupportedVertexBuffer) void {
    _ = self;
}

pub fn SetData(self: UnsupportedVertexBuffer, data: *anyopaque, size: usize) void {
    _ = self;
    _ = data;
    _ = size;
}

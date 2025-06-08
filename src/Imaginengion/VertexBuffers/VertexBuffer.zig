const std = @import("std");
const builtin = @import("builtin");

const VertexBufferElement = @import("VertexBufferElement.zig");

const Impl = switch (builtin.os.tag) {
    .windows => @import("OpenGLVertexBuffer.zig"),
    else => @import("UnsupportedVertexBuffer.zig"),
};

const VertexBuffer = @This();

mImpl: Impl,

pub fn Init(allocator: std.mem.Allocator, size: usize) VertexBuffer {
    return VertexBuffer{
        .mImpl = Impl.Init(allocator, size),
    };
}

pub fn Deinit(self: VertexBuffer) void {
    self.mImpl.Deinit();
}

pub fn Bind(self: VertexBuffer) void {
    self.mImpl.Bind();
}

pub fn Unbind(self: VertexBuffer) void {
    self.mImpl.Unbind();
}

pub fn SetData(self: VertexBuffer, data: *anyopaque, size: usize, offset: u32) void {
    self.mImpl.SetData(data, size, offset);
}

pub fn SetLayout(self: *VertexBuffer, layout: std.ArrayList(VertexBufferElement)) !void {
    try self.mImpl.SetLayout(layout);
}

pub fn SetStride(self: *VertexBuffer, stride: usize) void {
    self.mImpl.SetStride(stride);
}

pub fn GetLayout(self: VertexBuffer) std.ArrayList(VertexBufferElement) {
    return self.mImpl.GetLayout();
}

pub fn GetStride(self: VertexBuffer) usize {
    return self.mImpl.GetStride();
}

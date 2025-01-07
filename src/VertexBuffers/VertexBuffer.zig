const std = @import("std");
const builtin = @import("builtin");

const VertexBufferElement = @import("VertexBufferElement.zig");

const Impl = switch (builtin.os.tag) {
    .windows => @import("OpenGLVertexBuffer.zig"),
    else => @import("UnsupportedVertexBuffer.zig"),
};

const VertexBuffer = @This();

mImpl: Impl,
mBufferID: c_uint,
mLayout: std.ArrayList(VertexBufferElement),
mStride: c_uint,

pub fn Init(size: usize) VertexBuffer {
    return VertexBuffer{
        ._Impl = Impl.Init(size),
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

pub fn SetData(self: VertexBuffer, data: *anyopaque, size: usize) void {
    self.mImpl.SetData(data, size);
}

pub fn SetLayout(self: VertexBuffer, layout: std.ArrayList(VertexBufferElement)) void {
    self.mLayout = layout.clone();
}

pub fn SetStride(self: VertexBuffer, stride: u32) void {
    self.mStride = stride;
}

pub fn GetLayout(self: VertexBuffer) std.ArrayList(VertexBuffer) {
    return self.mLayout;
}

pub fn GetStride(self: VertexBuffer) u32 {
    return self.mStride;
}

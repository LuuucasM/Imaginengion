const std = @import("std");
const builtin = @import("builtin");

const VertexBufferElement = @import("VertexBufferElement.zig");

const Impl = switch (builtin.os.tag) {
    .windows => @import("OpenGLVertexBuffer.zig"),
    else => @import("UnsupportedVertexBuffer.zig"),
};

const VertexBuffer = @This();

mBufferID: c_uint,
mLayout: std.ArrayList(VertexBufferElement),
mStride: c_uint,

pub fn Init(size: usize) VertexBuffer {
    const new_vb = VertexBuffer{
        .mBufferID = 0,
        .mLayout = std.ArrayList(VertexBufferElement).init(0),
        .mStride = 0,
        ._Impl = undefined,
    };
    Impl.Init(size, &new_vb.mBufferID);
    return new_vb;
}

pub fn Deinit(self: VertexBuffer) void {
    Impl.Deinit(&self.mBufferID);
}

pub fn Bind(self: VertexBuffer) void {
    Impl.Bind(&self.mBufferID);
}

pub fn Unbind(self: VertexBuffer) void {
    _ = self;
    Impl.Unbind();
}

pub fn SetData(self: VertexBuffer, data: *anyopaque, size: usize) void {
    Impl.SetData(&self.mBufferID, data, size);
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

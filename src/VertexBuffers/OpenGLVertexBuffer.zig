const std = @import("std");
const glad = @import("../Core/CImports.zig").glad;
const VertexBufferElement = @import("VertexBufferElement.zig");

const OpenGLVertexBuffer = @This();

mBufferID: c_uint,
mCapacity: usize,
mLayout: std.ArrayList(VertexBufferElement),
mStride: c_uint,

pub fn Init(allocator: std.mem.Allocator, size: usize) OpenGLVertexBuffer {
    const new_vb = OpenGLVertexBuffer{
        .mBufferID = undefined,
        .mCapacity = size,
        .mLayout = std.ArrayList(VertexBufferElement).init(allocator),
        .mStride = 0,
    };
    glad.glCreateBuffers(1, &new_vb.mBufferID);
    glad.glBindBuffer(glad.GL_ARRAY_BUFFER, new_vb.mBufferID);
    glad.glBufferData(glad.GL_ARRAY_BUFFER, size, null, glad.GL_DYNAMIC_DRAW);
    return new_vb;
}

pub fn Deinit(self: OpenGLVertexBuffer) void {
    glad.glDeleteBuffers(1, &self.mBufferID);
}

pub fn Bind(self: OpenGLVertexBuffer) void {
    glad.glBindBuffer(glad.GL_ARRAY_BUFFER, self.mBufferID);
}

pub fn Unbind() void {
    glad.glBindBuffer(glad.GL_ARRAY_BUFFER, 0);
}

pub fn SetData(self: OpenGLVertexBuffer, data: *anyopaque, size: usize) void {
    if (size <= self.Capacity) {
        glad.glBindBuffer(glad.GL_ARRAY_BUFFER, self.mBufferID);
        glad.glBufferSubData(glad.GL_ARRAY_BUFFER, 0, size, data);
    } else {
        glad.glBindBuffer(glad.GL_ARRAY_BUFFER, self.mBufferID);
        glad.glNamedBufferData(self.mBufferID, size, data, glad.GL_DYNAMIC_DRAW);
    }
}

pub fn SetLayout(self: OpenGLVertexBuffer, layout: std.ArrayList(VertexBufferElement)) void {
    self.mLayout = layout.clone();
}

pub fn SetStride(self: OpenGLVertexBuffer, stride: u32) void {
    self.mStride = stride;
}

pub fn GetLayout(self: OpenGLVertexBuffer) std.ArrayList(VertexBufferElement) {
    return self.mLayout;
}

pub fn GetStride(self: OpenGLVertexBuffer) u32 {
    return self.mStride;
}

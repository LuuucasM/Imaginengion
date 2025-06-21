const std = @import("std");
const glad = @import("../Core/CImports.zig").glad;
const VertexBufferElement = @import("VertexBufferElement.zig");

const OpenGLVertexBuffer = @This();

mBufferID: c_uint,
mSize: usize,
mLayout: std.ArrayList(VertexBufferElement),
mStride: usize,

pub fn Init(allocator: std.mem.Allocator, size: usize) OpenGLVertexBuffer {
    var new_vb = OpenGLVertexBuffer{
        .mBufferID = undefined,
        .mSize = size,
        .mLayout = std.ArrayList(VertexBufferElement).init(allocator),
        .mStride = 0,
    };
    glad.glCreateBuffers(1, &new_vb.mBufferID);
    glad.glBindBuffer(glad.GL_ARRAY_BUFFER, new_vb.mBufferID);
    glad.glNamedBufferStorage(new_vb.mBufferID, @intCast(size), null, glad.GL_DYNAMIC_STORAGE_BIT);
    return new_vb;
}

pub fn Deinit(self: OpenGLVertexBuffer) void {
    self.mLayout.deinit();
    glad.glDeleteBuffers(1, &self.mBufferID);
}

pub fn Bind(self: OpenGLVertexBuffer) void {
    glad.glBindBuffer(glad.GL_ARRAY_BUFFER, self.mBufferID);
}

pub fn Unbind() void {
    glad.glBindBuffer(glad.GL_ARRAY_BUFFER, 0);
}

pub fn SetData(self: OpenGLVertexBuffer, data: *anyopaque, size: usize, offset: u32) void {
    if (size > self.mSize) {
        glad.glNamedBufferData(self.mBufferID, @intCast(size), data, glad.GL_DYNAMIC_COPY);
    } else {
        glad.glNamedBufferSubData(self.mBufferID, offset, @intCast(size), data);
    }
}

pub fn SetLayout(self: *OpenGLVertexBuffer, layout: std.ArrayList(VertexBufferElement)) !void {
    self.mLayout.clearRetainingCapacity();
    try self.mLayout.appendSlice(layout.items);
    self.mLayout.shrinkAndFree(layout.items.len);
}

pub fn SetStride(self: *OpenGLVertexBuffer, stride: usize) void {
    self.mStride = stride;
}

pub fn GetLayout(self: OpenGLVertexBuffer) std.ArrayList(VertexBufferElement) {
    return self.mLayout;
}

pub fn GetStride(self: OpenGLVertexBuffer) usize {
    return self.mStride;
}

const std = @import("std");
const glad = @import("../Core/CImports.zig").glad;
const VertexBufferElement = @import("VertexBufferElement.zig");

const OpenGLVertexBuffer = @This();

mBufferID: c_uint,
mCapacity: usize,
mLayout: std.ArrayList(VertexBufferElement),
mStride: c_uint,

pub fn Init(allocator: std.mem.Allocator, size: usize) OpenGLVertexBuffer {
    var new_vb = OpenGLVertexBuffer{
        .mBufferID = undefined,
        .mCapacity = size,
        .mLayout = std.ArrayList(VertexBufferElement).init(allocator),
        .mStride = 0,
    };
    glad.glCreateBuffers(1, &new_vb.mBufferID);
    glad.glBindBuffer(glad.GL_ARRAY_BUFFER, new_vb.mBufferID);
    glad.glBufferData(glad.GL_ARRAY_BUFFER, @intCast(size), null, glad.GL_DYNAMIC_DRAW);
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

pub fn SetData(self: OpenGLVertexBuffer, data: *anyopaque, size: usize) void {
    glad.glBindBuffer(glad.GL_ARRAY_BUFFER, self.mBufferID);
    glad.glBufferSubData(glad.GL_ARRAY_BUFFER, 0, @intCast(size), data);

    const mapped_data = glad.glMapBuffer(glad.GL_ARRAY_BUFFER, glad.GL_READ_ONLY);
    if (mapped_data != null) {
        // Cast the opaque pointer to a float array pointer
        const vertices: [*]const f32 = @ptrCast(@alignCast(mapped_data));
        var i: usize = 0;
        while (i < 12) : (i += 3) { // Print first 4 vertices
            std.debug.print("Vertex {}: ({}, {}, {})\n", .{ i / 3, vertices[i], vertices[i + 1], vertices[i + 2] });
        }
        _ = glad.glUnmapBuffer(glad.GL_ARRAY_BUFFER);
    }
}

pub fn SetLayout(self: *OpenGLVertexBuffer, layout: std.ArrayList(VertexBufferElement)) !void {
    self.mLayout.clearRetainingCapacity();
    try self.mLayout.appendSlice(layout.items);
    self.mLayout.shrinkAndFree(layout.items.len);
}

pub fn SetStride(self: *OpenGLVertexBuffer, stride: u32) void {
    self.mStride = stride;
}

pub fn GetLayout(self: OpenGLVertexBuffer) std.ArrayList(VertexBufferElement) {
    return self.mLayout;
}

pub fn GetStride(self: OpenGLVertexBuffer) u32 {
    return self.mStride;
}

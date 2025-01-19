const std = @import("std");
const glad = @import("../Core/CImports.zig").glad;

const VertexBuffer = @import("../VertexBuffers/VertexBuffer.zig");
const IndexBuffer = @import("../IndexBuffers/IndexBuffer.zig");
const ShaderDataType = @import("../Shaders/Shaders.zig").ShaderDataType;

const OpenGLVertexArray = @This();

mArrayID: c_uint,
mVertexBuffers: std.ArrayList(VertexBuffer),
mIndexBuffer: IndexBuffer,

pub fn Init(allocator: std.mem.Allocator) OpenGLVertexArray {
    var new_va = OpenGLVertexArray{
        .mArrayID = undefined,
        .mVertexBuffers = std.ArrayList(VertexBuffer).init(allocator),
        .mIndexBuffer = undefined,
    };

    glad.glCreateVertexArrays(1, &new_va.mArrayID);

    return new_va;
}

pub fn Deinit(self: OpenGLVertexArray) void {
    glad.glDeleteVertexArrays(1, &self.mArrayID);
}

pub fn Bind(self: OpenGLVertexArray) void {
    glad.glBindVertexArray(self.mArrayID);
}

pub fn Unbind() void {
    glad.glBindVertexArray(0);
}

pub fn AddVertexBuffer(self: *OpenGLVertexArray, new_vertex_buffer: VertexBuffer) !void {
    self.Bind();
    new_vertex_buffer.Bind();

    for (new_vertex_buffer.GetLayout().items, 0..) |element, i| {
        glad.glEnableVertexAttribArray(@intCast(i));

        if (element.mType == .Bool or element.mType == .UInt or
            element.mType == .Int or element.mType == .Int2 or
            element.mType == .Int3 or element.mType == .Int4)
        {
            glad.glVertexAttribIPointer(
                @intCast(i),
                element.GetComponentCount(),
                ShaderDataTypeToOpenGLBaseType(element.mType),
                @intCast(new_vertex_buffer.GetStride()),
                @as(*anyopaque, @ptrFromInt(@as(usize, element.mOffset))),
            );
        } else {
            glad.glVertexAttribPointer(
                @intCast(i),
                element.GetComponentCount(),
                ShaderDataTypeToOpenGLBaseType(element.mType),
                if (element.mIsNormalized) glad.GL_TRUE else glad.GL_FALSE,
                @intCast(new_vertex_buffer.GetStride()),
                @as(*anyopaque, @ptrFromInt(@as(usize, element.mOffset))),
            );
        }
    }
    try self.mVertexBuffers.append(new_vertex_buffer);
}

pub fn SetIndexBuffer(self: *OpenGLVertexArray, new_index_buffer: IndexBuffer) void {
    self.Bind();
    new_index_buffer.Bind();
    self.mIndexBuffer = new_index_buffer;
}

fn ShaderDataTypeToOpenGLBaseType(data_type: ShaderDataType) glad.GLenum {
    return switch (data_type) {
        .Float => glad.GL_FLOAT,
        .Float2 => glad.GL_FLOAT,
        .Float3 => glad.GL_FLOAT,
        .Float4 => glad.GL_FLOAT,
        .Mat3 => glad.GL_FLOAT,
        .Mat4 => glad.GL_FLOAT,
        .UInt => glad.GL_UNSIGNED_INT,
        .Int => glad.GL_INT,
        .Int2 => glad.GL_INT,
        .Int3 => glad.GL_INT,
        .Int4 => glad.GL_INT,
        .Bool => glad.GL_BOOL,
    };
}

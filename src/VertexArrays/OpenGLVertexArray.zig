const std = @import("std");
const glad = @import("../Core/CImports.zig").glad;

const VertexBuffer = @import("../VertexBuffers/VertexBuffer.zig");
const IndexBuffer = @import("../IndexBuffers/IndexBuffer.zig");
const ShaderDataType = @import("../Shaders/Shaders.zig").ShaderDataType;

const OpenGLVertexArray = @This();

pub fn Init(array_id: *c_uint) void {
    glad.glCreateVertexArrays(1, array_id);
}

pub fn Deinit(array_id: *c_uint) void {
    glad.glDeleteVertexArrays(1, array_id);
}

pub fn Bind(array_id: c_uint) void {
    glad.glBindVertexArray(array_id);
}

pub fn Unbind() void {
    glad.glBindVertexArray(0);
}

pub fn AddVertexBuffer(new_vertex_buffer: VertexBuffer) void {
    new_vertex_buffer.Bind();

    for (new_vertex_buffer.mLayout.items, 0..) |element, i| {
        glad.glEnableVertexAttribArray(i);

        if (element.mType == .Bool or element.mType == .UInt or
            element.mType == .Int or element.mType == .Int2 or
            element.mType == .Int3 or element.mType == .Int4)
        {
            glad.glVertexAttribIPointer(
                i,
                element.GetComponentCount(),
                ShaderDataTypeToOpenGLBaseType(element.mType),
                new_vertex_buffer.GetStride(),
                @as(*anyopaque, @ptrFromInt(@as(usize, element.mOffset))),
            );
        } else {
            glad.glVertexAttribPointer(
                i,
                element.GetComponentCount(),
                ShaderDataTypeToOpenGLBaseType(element.mType),
                if (element.mIsNormalized) glad.GL_TRUE else glad.GL_FALSE,
                VertexBuffer.GetStride(),
                @as(*anyopaque, @ptrFromInt(@as(usize, element.mOffset))),
            );
        }
    }
}

pub fn SetIndexBuffer(index_buffer: IndexBuffer) void {
    index_buffer.Bind();
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

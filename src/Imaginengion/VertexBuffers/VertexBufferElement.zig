const ShaderDataType = @import("../Shaders/Shaders.zig").ShaderDataType;
const ShaderDataTypeSize = @import("../Shaders/Shaders.zig").ShaderDataTypeSize;

const VertexBufferElement = @This();

mType: ShaderDataType,
mSize: u32,
mOffset: u32,
mIsNormalized: bool,

pub fn Init(data_type: ShaderDataType, normalized: bool) VertexBufferElement {
    return VertexBufferElement{
        .mType = data_type,
        .mSize = ShaderDataTypeSize(data_type),
        .mOffset = 0,
        .mIsNormalized = normalized,
    };
}

pub fn GetComponentCount(self: VertexBufferElement) c_int {
    return switch (self.mType) {
        .Float => 1,
        .Float2 => 2,
        .Float3 => 3,
        .Float4 => 4,
        .Mat3 => 3 * 3,
        .Mat4 => 4 * 4,
        .UInt => 1,
        .Int => 1,
        .Int2 => 2,
        .Int3 => 3,
        .Int4 => 4,
        .Bool => 1,
    };
}

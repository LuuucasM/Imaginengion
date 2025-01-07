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

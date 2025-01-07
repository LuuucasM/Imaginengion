pub const ShaderDataType = enum(u16) {
    Float,
    Float2,
    Float3,
    Float4,
    Mat3,
    Mat4,
    UInt,
    Int,
    Int2,
    Int3,
    Int4,
    Bool,
};

pub fn ShaderDataTypeSize(data_type: ShaderDataType) u32 {
    return switch (data_type) {
        .Float => 4,
        .Float2 => 4 * 2,
        .Float3 => 4 * 3,
        .Float4 => 4 * 4,
        .Mat3 => 4 * 3 * 3,
        .Mat4 => 4 * 4 * 4,
        .UInt => 4,
        .Int => 4,
        .Int2 => 4 * 2,
        .Int3 => 4 * 3,
        .Int4 => 4 * 4,
        .Bool => 1,
    };
}

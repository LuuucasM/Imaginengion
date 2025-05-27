const std = @import("std");
const builtin = @import("builtin");
const VertexBufferElement = @import("../VertexBuffers/VertexBufferElement.zig");

const Impl = switch (builtin.os.tag) {
    .windows => @import("OpenGLShader.zig"),
    else => @import("UnsupportedShader.zig"),
};

const LinAlg = @import("../Math/LinAlg.zig");
const Vec2f32 = LinAlg.Vec2f32;
const Vec3f32 = LinAlg.Vec3f32;
const Vec4f32 = LinAlg.Vec4f32;
const Mat3f32 = LinAlg.Mat3f32;
const Mat4f32 = LinAlg.Mat4f32;

const Shader = @This();

pub const ShaderDataType = enum(u4) {
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

pub fn StrToDataType(name: []const u8) ShaderDataType {
    if (std.mem.eql(u8, name, "float")) return ShaderDataType.Float;
}

mImpl: Impl,

pub fn Init(allocator: std.mem.Allocator, abs_path: []const u8) !Shader {
    return Shader{
        .mImpl = try Impl.Init(allocator, abs_path),
    };
}

pub fn Deinit(self: *Shader) void {
    self.mImpl.Deinit();
}

pub fn Bind(self: Shader) void {
    self.mImpl.Bind();
}

pub fn Unbind(self: Shader) void {
    self.mImpl.Unbind();
}

pub fn GetLayout(self: Shader) std.ArrayList(VertexBufferElement) {
    return self.mImpl.GetLayout();
}

pub fn GetStride(self: Shader) usize {
    return self.mImpl.GetStride();
}

pub fn SetUniform_Bool(self: Shader, name: []const u8, value: bool) void {
    self.mImpl.SetUniform_Bool(name, value);
}
pub fn SetUniform_Int(self: Shader, name: []const u8, value: i32) void {
    self.mImpl.SetUniform_Int(name, value);
}
pub fn SetUniform_IntArray(self: Shader, name: []const u8, value: *i32) void {
    self.mImpl.SetUniform_IntArray(name, value);
}
pub fn SetUniform_Float(self: Shader, name: []const u8, value: f32) void {
    self.mImpl.SetUniform_Float(name, value);
}
pub fn SetUniform_Vec2(self: Shader, name: []const u8, value: Vec2f32) void {
    self.mImpl.SetUniform_Vec2(name, value);
}
pub fn SetUniform_Vec3(self: Shader, name: []const u8, value: Vec3f32) void {
    self.mImpl.SetUniform_Vec3(name, value);
}
pub fn SetUniform_Vec4(self: Shader, name: []const u8, value: Vec4f32) void {
    self.mImpl.SetUniform_Vec4(name, value);
}
pub fn SetUniform_Mat3(self: Shader, name: []const u8, value: Mat3f32) void {
    self.mImpl.SetUniform_Mat3(name, value);
}
pub fn SetUniform_Mat4(self: Shader, name: []const u8, value: Mat4f32) void {
    self.mImpl.SetUniform_Mat4(name, value);
}

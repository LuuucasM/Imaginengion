const std = @import("std");

const VertexBufferElement = @import("../VertexBuffers/VertexBufferElement.zig");

const LinAlg = @import("../Math/LinAlg.zig");
const Vec2f32 = LinAlg.Vec2f32;
const Vec3f32 = LinAlg.Vec3f32;
const Vec4f32 = LinAlg.Vec4f32;
const Mat3f32 = LinAlg.Mat3f32;
const Mat4f32 = LinAlg.Mat4f32;

const OpenGLShader = @This();

mBufferElements: std.ArrayList(VertexBufferElement),
mUniforms: std.AutoHashMap(u32, i32),
mBufferStride: u32,
mShaderID: u32,
mName: []const u8,

pub fn Init(allocator: std.mem.Allocator, abs_path: []const u8) OpenGLShader {
    _ = abs_path;
    const new_shader = OpenGLShader{
        .mBufferElements = std.ArrayList(VertexBufferElement).init(allocator),
        .mUniforms = std.AutoHashMap(u32, i32).init(allocator),
        .mBufferStride = 0,
        .mShaderID = 0,
        .mName = undefined,
    };
    return new_shader;
}

pub fn Deinit(self: OpenGLShader) void {
    self.mImpl.Deinit();
}

pub fn Bind(self: OpenGLShader) void {
    self.mImpl.Bind();
}

pub fn Unbind(self: OpenGLShader) void {
    self.mImpl.Unbind();
}

pub fn SetUniform_Bool(self: OpenGLShader, name: []const u8, value: bool) void {
    self.mImpl.SetUniform_Bool(name, value);
}
pub fn SetUniform_Int(self: OpenGLShader, name: []const u8, value: i32) void {
    self.mImpl.SetUniform_Int(name, value);
}
pub fn SetUniform_IntArray(self: OpenGLShader, name: []const u8, value: *i32) void {
    self.mImpl.SetUniform_IntArray(name, value);
}
pub fn SetUniform_Float(self: OpenGLShader, name: []const u8, value: f32) void {
    self.mImpl.SetUniform_Float(name, value);
}
pub fn SetUniform_Vec2(self: OpenGLShader, name: []const u8, value: Vec2f32) void {
    self.mImpl.SetUniform_Vec2(name, value);
}
pub fn SetUniform_Vec3(self: OpenGLShader, name: []const u8, value: Vec3f32) void {
    self.mImpl.SetUniform_Vec3(name, value);
}
pub fn SetUniform_Vec4(self: OpenGLShader, name: []const u8, value: Vec4f32) void {
    self.mImpl.SetUniform_Vec4(name, value);
}
pub fn SetUniform_Mat3(self: OpenGLShader, name: []const u8, value: Mat3f32) void {
    self.mImpl.SetUniform_Mat3(name, value);
}
pub fn SetUniform_Mat4(self: OpenGLShader, name: []const u8, value: Mat4f32) void {
    self.mImpl.SetUniform_Mat4(name, value);
}

fn ReadFile() void {}
fn PreProcess() void {}
fn Compile() void {}
fn CreateLayout() void {}
fn DiscoverUniforms() void {}

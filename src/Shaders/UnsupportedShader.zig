const std = @import("std");

const LinAlg = @import("../Math/LinAlg.zig");
const Vec2f32 = LinAlg.Vec2f32;
const Vec3f32 = LinAlg.Vec3f32;
const Vec4f32 = LinAlg.Vec4f32;
const Mat3f32 = LinAlg.Mat3f32;
const Mat4f32 = LinAlg.Mat4f32;

const UnsupportedShader = @This();

pub fn Init(allocator: std.mem.Allocator, abs_path: []const u8) UnsupportedShader {
    _ = allocator;
    _ = abs_path;
    Unsupported();
}

pub fn Deinit(self: UnsupportedShader) void {
    _ = self;
    Unsupported();
}

pub fn Bind(self: UnsupportedShader) void {
    _ = self;
    Unsupported();
}

pub fn Unbind(self: UnsupportedShader) void {
    _ = self;
    Unsupported();
}

pub fn SetUniform_Bool(self: UnsupportedShader, name: []const u8, value: bool) void {
    _ = self;
    _ = name;
    _ = value;
    Unsupported();
}
pub fn SetUniform_Int(self: UnsupportedShader, name: []const u8, value: i32) void {
    _ = self;
    _ = name;
    _ = value;
    Unsupported();
}
pub fn SetUniform_IntArray(self: UnsupportedShader, name: []const u8, value: *i32) void {
    _ = self;
    _ = name;
    _ = value;
    Unsupported();
}
pub fn SetUniform_Float(self: UnsupportedShader, name: []const u8, value: f32) void {
    _ = self;
    _ = name;
    _ = value;
    Unsupported();
}
pub fn SetUniform_Vec2(self: UnsupportedShader, name: []const u8, value: Vec2f32) void {
    _ = self;
    _ = name;
    _ = value;
    Unsupported();
}
pub fn SetUniform_Vec3(self: UnsupportedShader, name: []const u8, value: Vec3f32) void {
    _ = self;
    _ = name;
    _ = value;
    Unsupported();
}
pub fn SetUniform_Vec4(self: UnsupportedShader, name: []const u8, value: Vec4f32) void {
    _ = self;
    _ = name;
    _ = value;
    Unsupported();
}
pub fn SetUniform_Mat3(self: UnsupportedShader, name: []const u8, value: Mat3f32) void {
    _ = self;
    _ = name;
    _ = value;
    Unsupported();
}
pub fn SetUniform_Mat4(self: UnsupportedShader, name: []const u8, value: Mat4f32) void {
    _ = self;
    _ = name;
    _ = value;
    Unsupported();
}

fn Unsupported() noreturn {
    @compileError("Unsupported OS for RenderContext");
}

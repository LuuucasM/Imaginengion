const std = @import("std");
const AssetsList = @import("../Assets.zig").AssetsList;
const builtin = @import("builtin");
const VertexBufferElement = @import("../../VertexBuffers/VertexBufferElement.zig");
const Tracy = @import("../../Core/Tracy.zig");
const EngineContext = @import("../../Core/EngineContext.zig");

const Impl = switch (builtin.os.tag) {
    .windows => @import("Shaders/OpenGLShader.zig"),
    else => @import("Shaders/UnsupportedShader.zig"),
};

const LinAlg = @import("../../Math/LinAlg.zig");
const Vec2f32 = LinAlg.Vec2f32;
const Vec3f32 = LinAlg.Vec3f32;
const Vec4f32 = LinAlg.Vec4f32;
const Mat3f32 = LinAlg.Mat3f32;
const Mat4f32 = LinAlg.Mat4f32;

const ShaderAsset = @This();

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

pub const Name: []const u8 = "ShaderAsset";
pub const Ind: usize = blk: {
    for (AssetsList, 0..) |asset_type, i| {
        if (asset_type == ShaderAsset) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

mImpl: Impl = .{},

pub fn Init(self: *ShaderAsset, engine_context: *EngineContext, abs_path: []const u8, rel_path: []const u8, asset_file: std.fs.File) !void {
    const zone = Tracy.ZoneInit("Shader Init", @src());
    defer zone.Deinit();
    try self.mImpl.Init(engine_context, abs_path, rel_path, asset_file);
}

pub fn Deinit(self: *ShaderAsset, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("Shader Deinit", @src());
    defer zone.Deinit();
    try self.mImpl.Deinit(engine_context);
}

pub fn Bind(self: ShaderAsset) void {
    const zone = Tracy.ZoneInit("Shader Bind", @src());
    defer zone.Deinit();
    self.mImpl.Bind();
}

pub fn Unbind(self: ShaderAsset) void {
    const zone = Tracy.ZoneInit("Shader Unbind", @src());
    defer zone.Deinit();
    self.mImpl.Unbind();
}

pub fn GetLayout(self: ShaderAsset) std.ArrayList(VertexBufferElement) {
    const zone = Tracy.ZoneInit("Shader GetLayout", @src());
    defer zone.Deinit();
    return self.mImpl.GetLayout();
}

pub fn GetStride(self: ShaderAsset) usize {
    const zone = Tracy.ZoneInit("Shader GetStride", @src());
    defer zone.Deinit();
    return self.mImpl.GetStride();
}

pub fn SetUniform_Bool(self: ShaderAsset, name: []const u8, value: bool) void {
    const zone = Tracy.ZoneInit("Shader SetUniform_Bool", @src());
    defer zone.Deinit();
    self.mImpl.SetUniform_Bool(name, value);
}
pub fn SetUniform_Int(self: ShaderAsset, name: []const u8, value: i32) void {
    const zone = Tracy.ZoneInit("Shader SetUniform_Int", @src());
    defer zone.Deinit();
    self.mImpl.SetUniform_Int(name, value);
}
pub fn SetUniform_IntArray(self: ShaderAsset, name: []const u8, value: *i32) void {
    const zone = Tracy.ZoneInit("Shader SetUniform_IntArray", @src());
    defer zone.Deinit();
    self.mImpl.SetUniform_IntArray(name, value);
}
pub fn SetUniform_Float(self: ShaderAsset, name: []const u8, value: f32) void {
    const zone = Tracy.ZoneInit("Shader SetUniform_Float", @src());
    defer zone.Deinit();
    self.mImpl.SetUniform_Float(name, value);
}
pub fn SetUniform_Vec2(self: ShaderAsset, name: []const u8, value: Vec2f32) void {
    const zone = Tracy.ZoneInit("Shader SetUniform_Vec2", @src());
    defer zone.Deinit();
    self.mImpl.SetUniform_Vec2(name, value);
}
pub fn SetUniform_Vec3(self: ShaderAsset, name: []const u8, value: Vec3f32) void {
    const zone = Tracy.ZoneInit("Shader SetUniform_Vec3", @src());
    defer zone.Deinit();
    self.mImpl.SetUniform_Vec3(name, value);
}
pub fn SetUniform_Vec4(self: ShaderAsset, name: []const u8, value: Vec4f32) void {
    const zone = Tracy.ZoneInit("Shader SetUniform_Vec4", @src());
    defer zone.Deinit();
    self.mImpl.SetUniform_Vec4(name, value);
}
pub fn SetUniform_Mat3(self: ShaderAsset, name: []const u8, value: Mat3f32) void {
    const zone = Tracy.ZoneInit("Shader SetUniform_Mat3", @src());
    defer zone.Deinit();
    self.mImpl.SetUniform_Mat3(name, value);
}
pub fn SetUniform_Mat4(self: ShaderAsset, name: []const u8, value: Mat4f32) void {
    const zone = Tracy.ZoneInit("Shader SetUniform_Mat4", @src());
    defer zone.Deinit();
    self.mImpl.SetUniform_Mat4(name, value);
}

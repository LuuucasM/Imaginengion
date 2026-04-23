const std = @import("std");
const builtin = @import("builtin");
const AssetsList = @import("../Assets.zig").AssetsList;
const Texture2D = @This();
const EngineContext = @import("../../Core/EngineContext.zig");

const LinAlg = @import("../../Math/LinAlg.zig");
const Vec4f32 = LinAlg.Vec4f32;
const Vec2f32 = LinAlg.Vec2f32;

pub const TexOptions = struct {
    mColor: Vec4f32 = .{ 1.0, 1.0, 1.0, 1.0 },
    mTilingFactor: f32 = 1.0,
    mTexCoords: Vec4f32 = Vec4f32{ 0, 0, 1, 1 },
};

pub const TextureFormat = enum(u4) {
    None = 0,
    RGBA8 = 1,
    RGBA16F = 2,
    RGBA32F = 3,
    RG32F = 4,
    RED_INTEGER = 5,
    DEPTH32F = 6,
    DEPTH24STENCIL8 = 7,
};

pub const GenDescriptor = struct {
    width: usize,
    height: usize,
    is_render_target: bool,
    texture_format: TextureFormat,
};

const Impl = switch (builtin.os.tag) {
    .windows => @import("Texture2Ds/SDLGPUTexture2D.zig"),
    else => @import("Texture2Ds/UnsupportedTexture2D.zig"),
};

pub const Name: []const u8 = "Texture2D";
pub const Ind: usize = blk: {
    for (AssetsList, 0..) |asset_type, i| {
        if (asset_type == Texture2D) {
            break :blk i + 5; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

_Impl: Impl = .{},

pub fn Init(self: *Texture2D, engine_context: *EngineContext, abs_path: []const u8, rel_path: []const u8, asset_file: std.fs.File) !void {
    try self._Impl.Init(engine_context, abs_path, rel_path, asset_file);
}
pub fn InitGen(self: *Texture2D, engine_context: *EngineContext, descriptor: GenDescriptor) !void {
    try self._Impl.InitGen(engine_context, descriptor);
}
pub fn Deinit(self: *Texture2D, engine_context: *EngineContext) !void {
    try self._Impl.Deinit(engine_context);
}
pub fn GetWidth(self: Texture2D) usize {
    return self._Impl.GetWidth();
}
pub fn GetHeight(self: Texture2D) usize {
    return self._Impl.GetHeight();
}
pub fn GetTexture(self: Texture2D) *anyopaque {
    return self._Impl.GetTexture();
}
pub fn GetSampler(self: Texture2D) *anyopaque {
    return self._Impl.GetSampler();
}
pub fn Bind(self: *Texture2D, slot: usize) void {
    self._Impl.Bind(slot);
}
pub fn UpdateDataPath(self: *Texture2D, path: []const u8) !void {
    try self._Impl.UpdateDataPath(path);
}

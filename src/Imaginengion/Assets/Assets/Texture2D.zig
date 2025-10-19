const std = @import("std");
const builtin = @import("builtin");
const AssetsList = @import("../Assets.zig").AssetsList;
const Texture2D = @This();
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;

const LinAlg = @import("../../Math/LinAlg.zig");
const Vec4f32 = LinAlg.Vec4f32;
const Vec2f32 = LinAlg.Vec2f32;

pub const TexOptions = struct {
    mColor: Vec4f32 = .{ 1.0, 1.0, 1.0, 1.0 },
    mTilingFactor: f32 = 1.0,
    mTexCoords: Vec4f32 = Vec4f32{ 0, 0, 1, 1 },
};

const Impl = switch (builtin.os.tag) {
    .windows => @import("Texture2Ds/OpenGLTexture2D.zig"),
    else => @import("Texture2Ds/UnsupportedTexture2D.zig"),
};

mTexOptions: TexOptions = .{},
_Impl: Impl = .{},

pub fn Init(self: *Texture2D, asset_allocator: std.mem.Allocator, _: []const u8, rel_path: []const u8, asset_file: std.fs.File) !void {
    try self._Impl.Init(asset_allocator, asset_file, rel_path);
}

pub fn Deinit(self: Texture2D) !void {
    try self._Impl.Deinit();
}

pub fn GetWidth(self: Texture2D) usize {
    return self._Impl.GetWidth();
}
pub fn GetHeight(self: Texture2D) usize {
    return self._Impl.GetHeight();
}
pub fn GetID(self: Texture2D) c_uint {
    return self._Impl.GetID();
}
pub fn GetBindlessID(self: Texture2D) u64 {
    return self._Impl.GetBindlessID();
}
pub fn UpdateData(self: *Texture2D, data: *anyopaque, size: usize) void {
    self._Impl.UpdateData(data, size);
}
pub fn UpdateDataPath(self: *Texture2D, path: []const u8) !void {
    try self._Impl.UpdateDataPath(path);
}
pub fn Bind(self: *Texture2D, slot: usize) void {
    self._Impl.Bind(slot);
}
pub fn Unbind(self: Texture2D, slot: usize) void {
    self._Impl.Unbind(slot);
}

pub const Ind: usize = blk: {
    for (AssetsList, 0..) |asset_type, i| {
        if (asset_type == Texture2D) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

pub const Category: ComponentCategory = .Unique;

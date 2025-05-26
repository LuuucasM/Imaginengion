const std = @import("std");
const builtin = @import("builtin");
const AssetsList = @import("../Assets.zig").AssetsList;
const Texture2D = @This();

const Impl = switch (builtin.os.tag) {
    .windows => @import("Texture2Ds/OpenGLTexture2D.zig"),
    else => @import("Texture2Ds/UnsupportedTexture2D.zig"),
};

_Impl: Impl = undefined,

pub fn Init(allocator: std.mem.Allocator, abs_path: []const u8) !Texture2D {
    return Texture2D{
        ._Impl = try Impl.Init(allocator, abs_path),
    };
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
            break :blk i;
        }
    }
};

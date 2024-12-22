const builtin = @import("builtin");
const AssetsList = @import("../../Assets.zig").AssetsList;
const Texture2D = @This();

const Impl = switch (builtin.os.tag) {
    .windows => @import("OpenGLTexture2D.zig"),
    else => @import("UnsupportedTexture2D.zig"),
};

_Impl: Impl,

pub fn InitData(width: u32, height: u32, channels: u32, data: *anyopaque, size: usize) Texture2D {
    return Texture2D{
        ._Impl = Impl.InitData(width, height, channels, data, size),
    };
}

pub fn InitPath(path: []const u8) !Texture2D {
    return Texture2D{
        ._Impl = try Impl.InitPath(path),
    };
}

pub fn Deinit(self: Texture2D) void {
    self._Impl.Deinit();
}

pub fn GetWidth(self: Texture2D) u32 {
    return self._Impl.GetWidth();
}
pub fn GetHeight(self: Texture2D) u32 {
    return self._Impl.GetHeight();
}
pub fn GetID(self: Texture2D) u32 {
    return self._Impl.GetID();
}
pub fn UpdateData(self: *Texture2D, data: *anyopaque, size: usize) void {
    self._Impl.UpdateData(data, size);
}
pub fn UpdateDataPath(self: *Texture2D, path: []const u8) !void {
    try self._Impl.UpdateDataPath(path);
}
pub fn Bind(self: Texture2D, slot: u32) void {
    self._Impl.Bind(slot);
}
pub fn Unbind(self: Texture2D, slot: u32) void {
    self._Impl.Unbind(slot);
}

pub const Ind: usize = blk: {
    for (AssetsList, 0..) |asset_type, i| {
        if (asset_type == Texture2D) {
            break :blk i;
        }
    }
};

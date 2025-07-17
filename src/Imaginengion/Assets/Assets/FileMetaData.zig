const std = @import("std");
const AssetsList = @import("../Assets.zig").AssetsList;
const FileMetaData = @This();

pub const PathType = enum(u2) {
    Eng = 0,
    Prj = 1,
    Abs = 2,
};

mRelPath: std.ArrayList(u8) = undefined,
mLastModified: i128 = 0,
mSize: u64 = 0,
mHash: u64 = 0,
mPathType: PathType = .Eng,

pub fn Deinit(self: *FileMetaData) !void {
    self.mRelPath.deinit();
}

pub const Ind: usize = blk: {
    for (AssetsList, 0..) |asset_type, i| {
        if (asset_type == FileMetaData) {
            break :blk i;
        }
    }
};

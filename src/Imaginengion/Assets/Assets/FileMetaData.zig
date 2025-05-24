const std = @import("std");
const AssetsList = @import("../Assets.zig").AssetsList;
const FileMetaData = @This();

pub const PathType = enum(u2) {
    Eng = 0,
    Prj = 1,
    Abs = 2,
};

mRelPath: []const u8 = undefined,
mLastModified: i128 = 0,
mSize: u64 = 0,
mHash: u64 = 0,
mPathType: PathType = .Eng,

pub fn Deinit(_: *FileMetaData) !void {}

pub const Ind: usize = blk: {
    for (AssetsList, 0..) |asset_type, i| {
        if (asset_type == FileMetaData) {
            break :blk i;
        }
    }
};

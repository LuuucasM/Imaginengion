const std = @import("std");
const AssetsList = @import("../Assets.zig").AssetsList;
const FileMetaData = @This();
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;

pub const PathType = enum(u2) {
    Eng = 0,
    Prj = 1,
};

mRelPath: std.ArrayList(u8) = .{},
mLastModified: i128 = 0,
mSize: u64 = 0,
mHash: u64 = 0,
mPathType: PathType = .Eng,

_PathAllocator: std.mem.Allocator = undefined,

pub fn Deinit(self: *FileMetaData) !void {
    self.mRelPath.deinit(self._PathAllocator);
}

pub const Ind: usize = blk: {
    for (AssetsList, 0..) |asset_type, i| {
        if (asset_type == FileMetaData) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

pub const Category: ComponentCategory = .Unique;

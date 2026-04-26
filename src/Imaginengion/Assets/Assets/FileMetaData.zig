const std = @import("std");
const AssetsList = @import("../Assets.zig").AssetsList;
const FileMetaData = @This();
const EngineContext = @import("../../Core/EngineContext.zig");
const PathType = @import("../AssetManager.zig").PathType;

pub const Name: []const u8 = "FileMetaData";
pub const Ind: usize = blk: {
    for (AssetsList, 0..) |asset_type, i| {
        if (asset_type == FileMetaData) {
            break :blk i + 5; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

mRelPath: std.ArrayList(u8) = .empty,
mLastModified: i128 = 0,
mSize: u64 = 0,
mHash: u64 = 0,
mPathType: PathType = .Eng,

pub fn Deinit(self: *FileMetaData, engine_context: *EngineContext) !void {
    self.mRelPath.deinit(engine_context.EngineAllocator());
}

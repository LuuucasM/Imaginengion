const BuiltinComponentCount = @import("../../ECS/Components.zig").BuiltinComponentCount;
const std = @import("std");
const AssetsList = @import("../Assets.zig").AssetsList;
const FileMetaData = @This();
const EngineContext = @import("../../Core/EngineContext.zig");
const PathType = @import("../AssetManager.zig").PathType;

pub const Name: []const u8 = "FileMetaData";
pub const Ind: usize = blk: {
    for (AssetsList, 0..) |asset_type, i| {
        if (asset_type == FileMetaData) {
            break :blk i + BuiltinComponentCount;
        }
    }
};

mRelPath: std.ArrayList(u8) = .empty,
mPathType: PathType = .Eng,
mLastModified: std.Io.Timestamp = .zero,
mSize: u64 = 0,
mHash: u64 = 0,

pub fn Deinit(self: *FileMetaData, engine_context: *EngineContext) void {
    self.mRelPath.deinit(engine_context.EngineAllocator());
}

pub fn Clone(self: *const FileMetaData, engine_context: *EngineContext) !FileMetaData {
    var new_component = self.*;
    new_component.mRelPath = try self.mRelPath.clone(engine_context.EngineAllocator());
    return new_component;
}

pub fn Eql(self: *FileMetaData, engine_context: *EngineContext, file: std.Io.File, stat: std.Io.File.Stat) !bool {
    if (self.mLastModified.nanoseconds != stat.mtime.nanoseconds) {
        return false;
    }
    if (self.mSize != stat.size) {
        return false;
    }

    var file_hasher = std.hash.Fnv1a_64.init();
    var file_reader = file.reader(engine_context.Io(), &.{});
    const contents = try file_reader.interface.allocRemaining(engine_context.FrameAllocator(), std.Io.Limit.unlimited);
    file_hasher.update(contents);

    if (self.mHash != file_hasher.final()) {
        return false;
    }

    return true;
}

pub fn UpdateMetaData(self: *FileMetaData, engine_context: *EngineContext, file: std.Io.File, stat: std.Io.File.Stat) !void {
    self.mLastModified = stat.mtime;
    self.mSize = stat.size;

    var file_hasher = std.hash.Fnv1a_64.init();
    var file_reader = file.reader(engine_context.Io(), &.{});
    const contents = try file_reader.interface.allocRemaining(engine_context.FrameAllocator(), std.Io.Limit.unlimited);
    file_hasher.update(contents);

    self.mHash = file_hasher.final();
}

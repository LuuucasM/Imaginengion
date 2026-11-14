const std = @import("std");
const AssetsList = @import("../AComponents.zig").AssetsList;
const FileMetaData = @This();
const EngineContext = @import("../../Core/EngineContext.zig");
const PathType = @import("../../ECSManagers/AManager.zig").PathType;
const FileTimeAndSize = @import("../../PlatformUtils/PlatformUtils.zig").FileTimeAndSize;

pub const Name: []const u8 = "FileMetaData";

mRelPath: std.ArrayList(u8) = .empty,
mPathType: PathType = .Eng,
mLastModified: std.Io.Timestamp = .zero,
mSize: u64 = 0,
mHash: u64 = 0,

pub fn Deinit(self: *FileMetaData, _: *EngineContext, keep_allocator: std.mem.Allocator) void {
    self.mRelPath.deinit(keep_allocator);
}

pub fn Clone(self: *const FileMetaData, _: *EngineContext, keep_allocator: std.mem.Allocator) !FileMetaData {
    var new_component = self.*;
    new_component.mRelPath = try self.mRelPath.clone(keep_allocator);
    return new_component;
}

pub fn Eql(self: *FileMetaData, engine_context: *EngineContext, file: std.Io.File, stat: FileTimeAndSize) !bool {
    if (self.mLastModified.nanoseconds != stat.mtime.nanoseconds) {
        return false;
    }
    if (self.mSize != stat.size) {
        return false;
    }

    var file_hasher = std.hash.Fnv1a_64.init();
    var file_reader = file.reader(engine_context.Io(), &.{});
    const contents = try file_reader.interface.allocRemaining(engine_context.Scratch(), std.Io.Limit.unlimited);
    file_hasher.update(contents);

    if (self.mHash != file_hasher.final()) {
        return false;
    }

    return true;
}

pub fn UpdateMetaData(self: *FileMetaData, engine_context: *EngineContext, file: std.Io.File, stat: FileTimeAndSize) !void {
    self.mLastModified = stat.mtime;
    self.mSize = stat.size;

    var file_hasher = std.hash.Fnv1a_64.init();
    var file_reader = file.reader(engine_context.Io(), &.{});
    const contents = try file_reader.interface.allocRemaining(engine_context.Scratch(), std.Io.Limit.unlimited);
    file_hasher.update(contents);

    self.mHash = file_hasher.final();
}

const std = @import("std");
const AssetManager = @import("../ECSManagers/AManager.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const Components = @import("../ECSComponents/AComponents.zig");
const FileMetaData = Components.FileMetaData;
const ECSCore = @import("ECSObject.zig").Core;
const JsonUtils = @import("../Serializer/JsonUtils.zig");

const AssetHandle = @This();
pub const Type = u32;
pub const NullObject: Type = std.math.maxInt(Type);

const Core = ECSCore(AssetHandle);

pub const uninit: AssetHandle = .{
    .mID = NullObject,
    .mManager = undefined,
};

mID: Type,
mManager: *AssetManager,

pub fn GetAsset(self: AssetHandle, engine_context: *EngineContext, comptime component_type: type) !*component_type {
    return try self.mManager.GetAsset(engine_context, component_type, self.mID);
}

pub fn GetFileMetaData(self: AssetHandle) *FileMetaData {
    return self.mManager.GetFileMetaData(self.mID);
}

pub fn ReleaseAsset(self: *AssetHandle) void {
    if (self.mID != NullObject) {
        self.mManager.ReleaseAssetHandle(self);
    }
}

pub const GetName = Core.GetName;
pub const IsActive = Core.IsActive;
pub const Invalidate = Core.Invalidate;
pub const IsIDValid = Core.IsIDValid;

/// How an asset handle is stored in a file. Handles without a file (null or generated assets) are written as null.
const FileRef = struct {
    Path: []const u8,
    PathType: AssetManager.PathType,
};

pub fn jsonStringify(self: *const AssetHandle, jw: anytype) !void {
    if (!self.IsIDValid()) return jw.write(null);

    const file_data = self.GetFileMetaData();
    if (file_data.mPathType == .Gen) return jw.write(null);

    try jw.write(FileRef{ .Path = file_data.mRelPath.items, .PathType = file_data.mPathType });
}

pub fn jsonParse(frame_allocator: std.mem.Allocator, reader: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(reader.*))!AssetHandle {
    if (try reader.peekNextTokenType() == .null) {
        _ = try reader.next();
        return .uninit;
    }

    const file_ref = try std.json.innerParse(FileRef, frame_allocator, reader, options);

    const engine_context = JsonUtils.EngineContextFromAllocator(frame_allocator);
    return engine_context.mAssetManager.GetAssetHandle(engine_context, .{ .File = .{ .rel_path = file_ref.Path, .path_type = file_ref.PathType } }) catch |err| {
        //a missing asset should not stop the rest of the file from loading, the asset manager falls back to default assets
        std.log.err("Failed to load asset '{s}' ({s}) while deserializing: {}", .{ file_ref.Path, @tagName(file_ref.PathType), err });
        return .uninit;
    };
}

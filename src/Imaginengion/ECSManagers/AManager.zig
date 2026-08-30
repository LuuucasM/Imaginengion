const std = @import("std");

const ResolveReq = @import("../Serializer/Serializer.zig").ResolveReq;

const ECSManager = @import("../ECS/ECSManager.zig").ECSManager;

const Asset = @import("../ECSObjects/Asset.zig");
const AssetComponents = @import("../ECSComponents/AComponents.zig");
const AssetComponentsList = AssetComponents.ComponentsList;
const FileMetaData = AssetComponents.FileMetaData;
const AssetHandle = @import("../ECSObjects/AssetHandle.zig");
const EngineContext = @import("../Core/EngineContext.zig");

const AManager = @This();

pub const ECSManagerA = ECSManager(Asset.Type, &AssetComponentsList);

pub const EventType = enum {
    ECSRemove,
};

pub const PathType = enum {
    Eng,
    Prj,
    Gen,
};

pub const FileSource = struct {
    rel_path: []const u8,
    path_type: PathType,
};

pub const ComputedSource = struct {
    id: []const u8,
};

pub const AssetSource = union(enum) {
    File: FileSource,
    Computed: ComputedSource,
    Default: struct {},
    pub fn GetPathType(self: AssetSource) PathType {
        return switch (self) {
            .File => |f| f.path_type,
            .Computed => PathType.Gen,
            .Default => PathType.Eng,
        };
    }
};

pub const uninit: AManager = .{
    .mECSManager = .empty,
    .mUUIDToWorldID = .empty,
    .mResolveUUIDList = .empty,
    .mPathToIDEng = .empty,
    .mPathToIDPrj = .empty,
    .mPathToGen = .empty,
    .mCWD = undefined,
    .mCWDPath = .empty,
    .mProjectDirectory = null,
    .mProjectPath = .empty,
};

mECSManager: ECSManagerA,

mUUIDToWorldID: std.AutoHashMapUnmanaged(u64, AssetHandle.Type),
mResolveUUIDList: std.ArrayList(ResolveReq),

mEventManager: 

mCWD: std.Io.Dir,
mCWDPath: std.ArrayList(u8),
mProjectDirectory: ?std.Io.Dir,
mProjectPath: std.ArrayList(u8),

pub fn Init(self: *AManager, engine_context: *EngineContext) !void {
    self.mECSManager.Init(engine_context.EngineAllocator());

    self.mCWD = std.Io.Dir.cwd();
    const cwd_path = try self.mCWD.realPathFileAlloc(engine_context.Io(), ".", engine_context.FrameAllocator());
    _ = try self.mCWDPath.print(engine_context.EngineAllocator(), "{s}", .{cwd_path});
}

//From current Asset Manager
pub fn Setup(self: *AManager, engine_context: *EngineContext) !void {}

pub fn Deinit(self: *AManager, engine_context: *EngineContext) void {}

pub fn GetAssetHandle(self: *AManager, engine_context: *EngineContext, asset_source: AssetSource) !void {}

pub fn ReleaseAssetHandle(self: *AManager, asset_handle: *AssetHandle) void {}

pub fn GetAsset(self: *AManager, engine_context: *EngineContext) !void {}

pub fn GetFileMetaData(self: *AManager, id: AssetHandle.Type) *FileMetaData {}

pub fn OnUpdate(self: *AManager, engine_context: *EngineContext) !void {}

pub fn OnNewProjectEvent(self: *AManager, engine_context: *EngineContext, abs_path: []const u8) !void {}

pub fn OnOpenProjectEvent(self: *AManager, engine_context: *EngineContext, abs_path: []const u8) !void {}

pub fn OpenFileStats(self: *AManager, engine_context: *EngineContext, rel_path: []const u8, path_type: PathType) !std.Io.File.Stat {}

pub fn OpenFile(self: *AManager, engine_context: *EngineContext, rel_path: []const u8, path_type: PathType) !std.Io.File {}

pub fn CloseFile(_: *AManager, io: std.Io, file: std.Io.File) void {}

pub fn GetAbsPath(self: *AManager, allocator: std.mem.Allocator, rel_path: []const u8, path_type: PathType) ![]const u8 {}

pub fn GetRelPath(self: *AManager, abs_path: []const u8) []const u8 {}

//From general managers
pub fn GetGroup(self: *AManager, engine_context: *EngineContext) std.ArrayList(AssetHandle.Type) {}

pub fn clearAndFree(self: *AManager, engine_context: *EngineContext) !void {}

pub fn ProcessEvents(self: *AManager, engine_context: *EngineContext, event_type: EventType) !void {}

pub fn Copy(self: *AManager, engine_context: *EngineContext, other_scene: *AManager) !void {}

pub fn AddUUID(self: *AManager, engine_allocator: std.mem.Allocator, uuid: u64, world_id: usize) !void {}

pub fn RemoveUUID(self: *AManager, uuid: u64) void {}

pub fn GetWorldID(self: *AManager, uuid: u64) ?usize {}

pub fn AddResolveUUID(self: *AManager, engine_allocator: std.mem.Allocator, resolve_req: ResolveReq) !void {}

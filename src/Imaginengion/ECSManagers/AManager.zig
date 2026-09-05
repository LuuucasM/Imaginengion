const std = @import("std");

const ResolveReq = @import("../Serializer/Serializer.zig").ResolveReq;

const ECSManager = @import("../ECS/ECSManager.zig").ECSManager;

const EventManager = @import("../Events/EventManager.zig").EventManager;
const EventData = @import("../Events/AManagerData.zig");

const AssetHandle = @import("../ECSObjects/AssetHandle.zig");
const AssetComponents = @import("../ECSComponents/AComponents.zig");
const AssetComponentsList = AssetComponents.ComponentsList;
const FileMetaData = AssetComponents.FileMetaData;
const AssetMetaData = AssetComponents.AssetMetaData;
const GenMetaData = AssetComponents.GenMetaData;
const EngineContext = @import("../Core/EngineContext.zig");

const AManager = @This();

pub const ECSManagerT = ECSManager(AssetHandle.Type, &AssetComponentsList);
pub const EventManagerT = EventManager(EventData.EventCategories, EventData.EventT(AssetHandle.Type));

pub const WorldIDT = AssetHandle.Type;

const Tracy = @import("../Core/Tracy.zig");

const ECSCore = @import("ECSManager.zig").Core;

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
    .mEventManager = .empty,
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

const Core = ECSCore(AManager);

mECSManager: ECSManagerT,

mUUIDToWorldID: std.AutoHashMapUnmanaged(u64, AssetHandle.Type),
mResolveUUIDList: std.ArrayList(ResolveReq),

mEventManager: EventManagerT,

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
///Setup needed to initialize "default" assets
pub fn Setup(self: *AManager, engine_context: *EngineContext) !void {
    const frame_allocator = engine_context.FrameAllocator();
    const io = engine_context.Io();

    //FILE META DATA =======================
    _ = try self._internal.DefaultFileMetaData.mRelPath.print(engine_context.EngineAllocator(), "default", .{});

    //TEXTURE 2D =========================
    const texture2d_rel_path = "src/Imaginengion/EngineAssets/textures/DefaultTexture.png";
    const texture2d_abs_path = try self.GetAbsPath(frame_allocator, texture2d_rel_path, .Eng);
    const texture2d_file = try std.Io.Dir.openFileAbsolute(io, texture2d_abs_path, .{});
    defer texture2d_file.close(io);
    try self._internal.DefaultTexture2D.Init(engine_context, texture2d_abs_path, texture2d_rel_path, texture2d_file);

    //TEXT ================================
    const text_rel_path = "src/Imaginengion/EngineAssets/fonts/default/static/ChironGoRoundTC-Regular.ttf";
    const text_abs_path = try self.GetAbsPath(frame_allocator, text_rel_path, .Eng);
    const text_file = try std.Io.Dir.openFileAbsolute(io, text_abs_path, .{});
    defer text_file.close(io);
    try self._internal.DefaultTextAsset.Init(engine_context, text_abs_path, text_rel_path, text_file);

    //AUDIO =================================
    const audio_rel_path = "src/Imaginengion/EngineAssets/sounds/DefaultSound.mp3";
    const audio_abs_path = try self.GetAbsPath(frame_allocator, audio_rel_path, .Eng);
    const audio_file = try std.Io.Dir.openFileAbsolute(io, audio_abs_path, .{});
    defer audio_file.close(io);
    try self._internal.DefaultAudioAsset.Init(engine_context, audio_abs_path, audio_rel_path, audio_file);
}

pub fn Deinit(self: *AManager, engine_context: *EngineContext) void {
    Core.Deinit(self, engine_context);
    self.mCWDPath.deinit(engine_context.EngineAllocator());
    self.mProjectPath.deinit(engine_context.EngineAllocator());

    self.mCWD.close(engine_context.Io());
    if (self.mProjectDirectory) |p_dir| p_dir.close(engine_context.Io());
}

pub fn GetAssetHandle(self: *AManager, engine_context: *EngineContext, asset_source: AssetSource) !void {
    if (asset_source == .Default) {
        return AssetHandle{
            .mID = AssetHandle.NullHandle,
            .mAssetManager = self,
        };
    }

    const asset_hash = switch (asset_source) {
        .File => |f| blk: {
            const abs_path = self.GetAbsPath(engine_context.FrameAllocator(), f.rel_path, f.path_type);
            break :blk ComputePathHash(abs_path);
        },
        .Computed => |c| ComputePathHash(c.id),
        .Default => unreachable,
    };

    const asset_id = self.mUUIDToWorldID.get(asset_hash);

    const engine_allocator = engine_context.EngineAllocator();

    if (asset_id) |id| {
        std.debug.assert(self.mECSManager.HasComponent(AssetMetaData, id));
        self.mECSManager.GetComponent(AssetMetaData, id).?.mRefs += 1;
        return AssetHandle{ .mID = id, .mAssetManager = self };
    } else {
        const new_asset_id = switch (asset_source) {
            .File => |f| try self.CreateAssetFile(engine_context, f),
            .Computed => try self.CreateAssetGen(engine_allocator),
            .Default => unreachable,
        };

        self.mECSManager.GetComponent(AssetMetaData, new_asset_id).?.mRefs += 1;

        try self.AddUUID(engine_allocator, asset_hash, new_asset_id);

        return AssetHandle{ .mID = new_asset_id, .mAssetManager = self };
    }
}

pub fn ReleaseAssetHandle(self: *AManager, asset_handle: *AssetHandle) void {
    const asset_meta_data = self.mECSManager.GetComponent(AssetMetaData, asset_handle.mID).?;
    asset_meta_data.mRefs -= 1;
    asset_handle.mID = AssetHandle.NullHandle;

    if (asset_meta_data.mRefs == 0) {
        //add a pending delete array to AManager
        //if refs is 0, add to pending delete array
        //in the OnUpdate function we can check for deletions and what not
    }
}

pub fn GetAsset(self: *AManager, engine_context: *EngineContext) !void {}

pub fn GetFileMetaData(self: *AManager, id: AssetHandle.Type) *FileMetaData {}

pub fn OnUpdate(self: *AManager, engine_context: *EngineContext) !void {}

pub fn OnNewProjectEvent(self: *AManager, engine_context: *EngineContext, abs_path: []const u8) !void {}

pub fn OnOpenProjectEvent(self: *AManager, engine_context: *EngineContext, abs_path: []const u8) !void {}

pub fn OpenFileStats(self: *AManager, engine_context: *EngineContext, rel_path: []const u8, path_type: PathType) !std.Io.File.Stat {
    const zone = Tracy.ZoneInit("AssetManager OpenFileStats", @src());
    defer zone.Deinit();

    switch (path_type) {
        .Eng => return try self.mCWD.statFile(engine_context.Io(), rel_path, .{}),
        .Prj => return try self.mProjectDirectory.?.statFile(engine_context.Io(), rel_path, .{}),
        .Gen => return error.NoFileToOpen,
    }
}

pub fn OpenFile(self: *AManager, engine_context: *EngineContext, rel_path: []const u8, path_type: PathType) !std.Io.File {
    const zone = Tracy.ZoneInit("AssetManager OpenFile", @src());
    defer zone.Deinit();
    switch (path_type) {
        .Eng => return try self.mCWD.openFile(engine_context.Io(), rel_path, .{}),
        .Prj => return try self.mProjectDirectory.?.openFile(engine_context.Io(), rel_path, .{}),
        .Gen => @panic("This shouldnt happen!"),
    }
}

pub fn CloseFile(_: *AManager, io: std.Io, file: std.Io.File) void {
    const zone = Tracy.ZoneInit("AssetManager CloseFile", @src());
    defer zone.Deinit();
    file.close(io);
}

pub fn GetFileStats(_: *AManager, file: std.fs.File) !std.fs.File.Stat {
    const zone = Tracy.ZoneInit("AssetManager GetFileStats", @src());
    defer zone.Deinit();
    return file.stat();
}

pub fn GetAbsPath(self: *AManager, allocator: std.mem.Allocator, rel_path: []const u8, path_type: PathType) ![]const u8 {
    const zone = Tracy.ZoneInit("AssetManager GetAbsPath", @src());
    defer zone.Deinit();

    switch (path_type) {
        .Eng => {
            return try std.fs.path.join(allocator, &[_][]const u8{ self.mCWDPath.items, rel_path });
        },
        .Prj => {
            return try std.fs.path.join(allocator, &[_][]const u8{ self.mProjectPath.items, rel_path });
        },
        .Gen => unreachable,
    }
}

pub fn GetRelPath(self: *AManager, abs_path: []const u8, path_type: PathType) []const u8 {
    const zone = Tracy.ZoneInit("AssetManager GetRelPath", @src());
    defer zone.Deinit();
    return switch (path_type) {
        .Eng => abs_path[self.mCWDPath.items.len + 1 ..],
        .Prj => abs_path[self.mProjectPath.items.len + 1 ..],
        .Gen => unreachable,
    };
}

//From general managers
pub fn GetGroup(self: *AManager, engine_context: *EngineContext) std.ArrayList(AssetHandle.Type) {}

pub fn clearAndFree(self: *AManager, engine_context: *EngineContext) !void {}

pub fn ProcessEvents(self: *AManager, engine_context: *EngineContext, event_type: EventType) !void {}

pub fn Copy(self: *AManager, engine_context: *EngineContext, other_scene: *AManager) !void {}

pub const AddUUID = Core.AddUUID;

pub fn RemoveUUID(self: *AManager, uuid: u64) void {}

pub fn GetWorldID(self: *AManager, uuid: u64) ?usize {}

pub fn AddResolveUUID(self: *AManager, engine_allocator: std.mem.Allocator, resolve_req: ResolveReq) !void {}

fn CreateAssetFile(self: *AManager, engine_context: *EngineContext, file_source: FileSource) !AssetHandle.Type {
    const zone = Tracy.ZoneInit("AssetManager CreateAssetFile", @src());
    defer zone.Deinit();

    const engine_allocator = engine_context.EngineAllocator();

    const new_asset_id = try self.mECSManager.CreateEntity(engine_allocator);

    _ = try self.mECSManager.AddComponent(engine_allocator, new_asset_id, AssetMetaData{ .mRefs = 0 });
    const file_meta_data = try self.mECSManager.AddComponent(engine_allocator, new_asset_id, FileMetaData{
        .mLastModified = .zero,
        .mSize = 0,
        .mHash = 0,
        .mPathType = file_source.path_type,
    });

    _ = try file_meta_data.mRelPath.print(engine_allocator, "{s}", .{file_source.rel_path});

    const file = try self.OpenFile(engine_context, file_source.rel_path, file_source.path_type);
    defer self.CloseFile(engine_context.Io(), file);
    const fstats = try file.stat(engine_context.Io());

    try UpdateAsset(engine_context, file_meta_data, file, fstats);

    return new_asset_id;
}

fn CreateAssetGen(self: *AManager, engine_allocator: std.mem.Allocator) !AssetHandle.Type {
    const zone = Tracy.ZoneInit("AssetManager CreateAssetGen", @src());
    defer zone.Deinit();

    const new_asset_id = try self.mECSManager.CreateEntity(engine_allocator);

    _ = try self.mECSManager.AddComponent(engine_allocator, new_asset_id, AssetMetaData{ .mRefs = 0 });
    _ = try self.mECSManager.AddComponent(engine_allocator, new_asset_id, GenMetaData{});

    return new_asset_id;
}

fn UpdateAsset(engine_context: *EngineContext, file_data: *FileMetaData, file: std.Io.File, fstats: std.Io.File.Stat) !void {
    const zone = Tracy.ZoneInit("AssetManager UpdateAsset", @src());
    defer zone.Deinit();

    var file_hasher = std.hash.Fnv1a_64.init();
    var file_reader = file.reader(engine_context.Io(), &.{});
    const contents = try file_reader.interface.allocRemaining(engine_context.FrameAllocator(), std.Io.Limit.unlimited);
    file_hasher.update(contents);

    file_data.mHash = file_hasher.final();
    file_data.mLastModified = fstats.mtime;
    file_data.mSize = fstats.size;
}

fn ComputePathHash(path: []const u8) u64 {
    const zone = Tracy.ZoneInit("AssetManager ComputePathHas", @src());
    defer zone.Deinit();
    var hasher = std.hash.Fnv1a_64.init();
    hasher.update(path);
    return hasher.final();
}

const std = @import("std");
const Set = @import("../Vendor/ziglang-set/src/hash_set/managed.zig").HashSetManaged;

const Assets = @import("Assets.zig");
const AssetMetaData = Assets.AssetMetaData;
const FileMetaData = Assets.FileMetaData;
const GenMetaData = Assets.GenMetaData;
const ScriptAsset = Assets.ScriptAsset;
const TextAsset = Assets.TextAsset;
const Texture2D = Assets.Texture2D;
const ShaderAsset = Assets.ShaderAsset;
const AudioAsset = Assets.AudioAsset;

const AssetsList = Assets.AssetsList;
const AssetHandle = @import("AssetHandle.zig");
const ArraySet = @import("../Vendor/ziglang-set/src/array_hash_set/managed.zig").ArraySetManaged;
const ECSManager = @import("../ECS/ECSManager.zig").ECSManager;
const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;
const EngineContext = @import("../Core/EngineContext.zig");

const Tracy = @import("../Core/Tracy.zig");

const AssetManager = @This();

const ASSET_DELETE_TIMEOUT_NS: i128 = 1_000_000_000;
const MAX_FILE_SIZE: usize = 4_000_000_000;

pub const AssetType = u32;

pub const ECSManagerAssets = ECSManager(AssetType, &AssetsList);

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

pub const PathType = enum(u2) {
    Eng = 0,
    Prj = 1,
    Gen = 2,
};

const InternalData = struct {
    DefaultFileMetaData: FileMetaData = .{},
    DefaultTexture2D: Texture2D = .{},
    DefaultTextAsset: TextAsset = .{},
    DefaultAudioAsset: AudioAsset = .{},
};
mAssetECS: ECSManagerAssets = undefined,
mPathToIDEng: std.AutoHashMapUnmanaged(u64, AssetType) = .empty,
mPathToIDPrj: std.AutoHashMapUnmanaged(u64, AssetType) = .empty,
mPathToIDGen: std.AutoHashMapUnmanaged(u64, AssetType) = .empty,
mCWD: std.Io.Dir = undefined,
mCWDPath: std.ArrayList(u8) = .empty,
mProjectDirectory: ?std.Io.Dir = undefined,
mProjectPath: std.ArrayList(u8) = .empty,

_internal: InternalData = .{},

pub fn Init(self: *AssetManager, engine_context: *EngineContext) !void {
    const engine_allocator = engine_context.EngineAllocator();

    try self.mAssetECS.Init(engine_allocator);

    self.mCWD = std.Io.Dir.cwd();
    const cwd_path = try self.mCWD.realPathFileAlloc(engine_context.Io(), ".", engine_context.FrameAllocator());
    _ = try self.mCWDPath.print(engine_allocator, "{s}", .{cwd_path});
}

pub fn Setup(self: *AssetManager, engine_context: *EngineContext) !void {
    const frame_allocator = engine_context.FrameAllocator();
    const io = engine_context.Io();

    //FILE META DATA =======================
    _ = try self._internal.DefaultFileMetaData.mRelPath.print(engine_context.EngineAllocator(), "default", .{});

    //TEXTURE 2D =========================
    const texture2d_rel_path = "assets/textures/DefaultTexture.png";
    const texture2d_abs_path = try self.GetAbsPath(frame_allocator, texture2d_rel_path, .Eng);
    const texture2d_file = try std.Io.Dir.openFileAbsolute(io, texture2d_abs_path, .{});
    defer texture2d_file.close(io);
    try self._internal.DefaultTexture2D.Init(engine_context, texture2d_abs_path, texture2d_rel_path, texture2d_file);

    //TEXT ================================
    const text_rel_path = "assets/fonts/default/static/ChironGoRoundTC-Regular.ttf";
    const text_abs_path = try self.GetAbsPath(frame_allocator, text_rel_path, .Eng);
    const text_file = try std.Io.Dir.openFileAbsolute(io, text_abs_path, .{});
    defer text_file.close(io);
    try self._internal.DefaultTextAsset.Init(engine_context, text_abs_path, text_rel_path, text_file);

    //AUDIO =================================
    const audio_rel_path = "assets/sounds/DefaultSound.mp3";
    const audio_abs_path = try self.GetAbsPath(frame_allocator, audio_rel_path, .Eng);
    const audio_file = try std.Io.Dir.openFileAbsolute(io, audio_abs_path, .{});
    defer audio_file.close(io);
    try self._internal.DefaultAudioAsset.Init(engine_context, audio_abs_path, audio_rel_path, audio_file);
}

pub fn Deinit(self: *AssetManager, engine_context: *EngineContext) !void {
    try self._internal.DefaultTexture2D.Deinit(engine_context);
    try self._internal.DefaultTextAsset.Deinit(engine_context);
    try self._internal.DefaultAudioAsset.Deinit(engine_context);
    self._internal.DefaultFileMetaData.mRelPath.deinit(engine_context.EngineAllocator());

    try self.mAssetECS.Deinit(engine_context);

    self.mPathToIDEng.deinit(engine_context.EngineAllocator());
    self.mPathToIDPrj.deinit(engine_context.EngineAllocator());
    self.mPathToIDGen.deinit(engine_context.EngineAllocator());

    self.mCWD.close();

    if (self.mProjectDirectory) |*dir| {
        dir.close();
    }

    self.mCWDPath.deinit(engine_context.EngineAllocator());
    self.mProjectPath.deinit(engine_context.EngineAllocator());
}

pub fn GetAssetHandleRef(self: *AssetManager, engine_context: *EngineContext, asset_source: AssetSource) !AssetHandle {
    if (asset_source == .Default) {
        return AssetHandle{
            .mID = AssetHandle.NullHandle,
            .mAssetManager = self,
        };
    }

    const asset_hash = switch (asset_source) {
        .File => |f| ComputePathHash(f.rel_path),
        .Computed => |c| ComputePathHash(c.id),
        .Default => @panic("shouldnt happen"),
    };

    const entity_id = switch (asset_source.GetPathType()) {
        .Eng => self.mPathToIDEng.get(asset_hash),
        .Prj => self.mPathToIDPrj.get(asset_hash),
        .Gen => self.mPathToIDGen.get(asset_hash),
    };

    const engine_allocator = engine_context.EngineAllocator();

    if (entity_id) |id| {
        std.debug.assert(self.mAssetECS.HasComponent(AssetMetaData, id));
        self.mAssetECS.GetComponent(AssetMetaData, id).?.mRefs += 1;
        return AssetHandle{ .mID = id, .mAssetManager = self };
    } else {
        const new_asset_id = switch (asset_source) {
            .File => |f| try self.CreateAssetFile(engine_context, f),
            .Computed => try self.CreateAssetGen(engine_allocator),
            .Default => unreachable,
        };

        self.mAssetECS.GetComponent(AssetMetaData, new_asset_id).?.mRefs += 1;

        _ = try switch (asset_source.GetPathType()) {
            .Eng => self.mPathToIDEng.put(engine_allocator, asset_hash, new_asset_id),
            .Prj => self.mPathToIDPrj.put(engine_allocator, asset_hash, new_asset_id),
            .Gen => self.mPathToIDGen.put(engine_allocator, asset_hash, new_asset_id),
        };

        return AssetHandle{ .mID = new_asset_id, .mAssetManager = self };
    }
}

pub fn ReleaseAssetHandleRef(self: *AssetManager, asset_handle: *AssetHandle) void {
    self.mAssetECS.GetComponent(AssetMetaData, asset_handle.mID).?.mRefs -= 1;
    asset_handle.mID = AssetHandle.NullHandle;
}

pub fn GetAsset(self: *AssetManager, engine_context: *EngineContext, comptime asset_type: type, asset_id: AssetType) !*asset_type {
    const zone = Tracy.ZoneInit("AssetManager::GetAsset", @src());
    defer zone.Deinit();

    _ValidateAssetType(asset_type);

    if (self.mAssetECS.IsActiveEntity(asset_id)) {
        if (self.mAssetECS.GetComponent(asset_type, asset_id)) |asset| {
            return asset;
        } else {
            const file_data = self.mAssetECS.GetComponent(FileMetaData, asset_id).?;
            std.debug.assert(file_data.mRelPath.items.len > 0);

            const abs_path = try self.GetAbsPath(engine_context.FrameAllocator(), file_data.mRelPath.items, file_data.mPathType);

            const asset_file = try self.OpenFile(engine_context, file_data.mRelPath.items, file_data.mPathType);
            defer self.CloseFile(engine_context.Io(), asset_file);

            var asset_component = asset_type{};
            asset_component.Init(engine_context, abs_path, file_data.mRelPath.items, asset_file) catch |err| {
                if (err == error.AssetInitFailed) return try self.GetDefaultAsset(asset_type) else return err;
            };

            return self.mAssetECS.AddComponent(engine_context.EngineAllocator(), asset_id, asset_component);
        }
    } else {
        return try self.GetDefaultAsset(asset_type);
    }
}

pub fn GetFileMetaData(self: *AssetManager, id: AssetType) *FileMetaData {
    if (self.mAssetECS.IsActiveEntity(id)) {
        return self.mAssetECS.GetComponent(FileMetaData, id).?;
    } else {
        return &self._internal.DefaultFileMetaData;
    }
}

pub fn OnUpdate(self: *AssetManager, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("AssetManager OnUpdate", @src());
    defer zone.Deinit();

    const frame_allocator = engine_context.FrameAllocator();

    const group = try self.mAssetECS.GetGroup(frame_allocator, GroupQuery{ .Component = FileMetaData });
    for (group.items) |entity_id| {
        const file_data = self.mAssetECS.GetComponent(FileMetaData, entity_id).?;
        if (file_data.mSize == 0) {
            try self.CheckAssetForDeletion(engine_context, entity_id);
            continue;
        }
        //then check if the asset path is still valid
        if (try self.GetFileStatsIfExists(file_data.mRelPath.items, file_data.mPathType, entity_id)) |file_stat| {

            //check to see if the file needs to be updated
            if (self.CheckModified(file_stat, file_data.mLastModified)) {
                const file = try self.OpenFile(engine_context, file_data.mRelPath.items, file_data.mPathType);
                try self.UpdateAsset(engine_context, entity_id, file, file_stat);
            }
        }
    }
}

pub fn GetGroup(self: AssetManager, frame_allocator: std.mem.Allocator, comptime query: GroupQuery) !std.ArrayList(AssetType) {
    return try self.mAssetECS.GetGroup(frame_allocator, query);
}

pub fn OnNewProjectEvent(self: *AssetManager, engine_allocator: std.mem.Allocator, abs_path: []const u8) !void {
    if (self.mProjectDirectory) |*dir| {
        dir.close();
        self.mProjectDirectory = null;
    }

    self.mProjectPath.clearAndFree(engine_allocator);

    self.mProjectDirectory = try std.fs.openDirAbsolute(abs_path, .{});

    _ = try self.mProjectPath.writer(engine_allocator).write(abs_path);
}

pub fn OnOpenProjectEvent(self: *AssetManager, engine_allocator: std.mem.Allocator, abs_path: []const u8) !void {
    if (self.mProjectDirectory) |*dir| {
        dir.close();
        self.mProjectDirectory = null;
    }

    self.mProjectPath.clearAndFree(engine_allocator);

    const dir_name = std.fs.path.dirname(abs_path).?;

    self.mProjectDirectory = try std.fs.openDirAbsolute(dir_name, .{});

    _ = try self.mProjectPath.writer(engine_allocator).write(dir_name);
}

pub fn OpenFileStats(self: *AssetManager, rel_path: []const u8, path_type: PathType) !std.fs.File.Stat {
    const zone = Tracy.ZoneInit("AssetManager OpenFileStats", @src());
    defer zone.Deinit();

    switch (path_type) {
        .Eng => return try self.mCWD.statFile(rel_path),
        .Prj => return try self.mProjectDirectory.?.statFile(rel_path),
    }
}

pub fn OpenFile(self: *AssetManager, engine_context: *EngineContext, rel_path: []const u8, path_type: PathType) !std.Io.File {
    const zone = Tracy.ZoneInit("AssetManager OpenFile", @src());
    defer zone.Deinit();
    switch (path_type) {
        .Eng => return try self.mCWD.openFile(engine_context.Io(), rel_path, .{}),
        .Prj => return try self.mProjectDirectory.?.openFile(engine_context.Io(), rel_path, .{}),
        .Gen => @panic("This shouldnt happen!"),
    }
}

pub fn CloseFile(_: *AssetManager, io: std.Io, file: std.Io.File) void {
    const zone = Tracy.ZoneInit("AssetManager CloseFile", @src());
    defer zone.Deinit();
    file.close(io);
}

pub fn GetFileStats(_: *AssetManager, file: std.fs.File) !std.fs.File.Stat {
    const zone = Tracy.ZoneInit("AssetManager GetFileStats", @src());
    defer zone.Deinit();
    return file.stat();
}

pub fn GetAbsPath(self: *AssetManager, allocator: std.mem.Allocator, rel_path: []const u8, path_type: PathType) ![]const u8 {
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

pub fn GetRelPath(self: *AssetManager, abs_path: []const u8) []const u8 {
    const zone = Tracy.ZoneInit("AssetManager GetRelPath", @src());
    defer zone.Deinit();
    return abs_path[self.mProjectPath.items.len + 1 ..];
}

pub fn ProcessDestroyedAssets(self: *AssetManager, engine_context: *EngineContext) !void {
    try self.mAssetECS.ProcessEvents(engine_context, .Remove, ECSManagerAssets.ECSCallbackList{});
}

fn GetDefaultAsset(self: *AssetManager, asset_type: type) !*asset_type {
    if (asset_type != Texture2D and asset_type != TextAsset and asset_type != AudioAsset) {
        return error.NoDefaultAsset;
    }
    return switch (asset_type) {
        Texture2D => &self._internal.DefaultTexture2D,
        TextAsset => &self._internal.DefaultTextAsset,
        AudioAsset => &self._internal.DefaultAudioAsset,
        else => @compileError("This should never happen! :)"),
    };
}

fn GetFileStatsIfExists(self: *AssetManager, rel_path: []const u8, path_type: PathType, entity_id: AssetType) !?std.fs.File.Stat {
    const zone = Tracy.ZoneInit("AssetManager GetFileStatsIfExists", @src());
    defer zone.Deinit();

    return self.OpenFileStats(rel_path, path_type) catch |err| {
        if (err == error.FileNotFound) {
            self.MarkAssetToDelete(entity_id);
            return null;
        }
        return null;
    };
}

fn GetFileIfExists(_: *AssetManager, engine_context: *EngineContext, rel_path: []const u8, path_type: PathType, entity_id: AssetType) !?std.fs.File {
    const zone = Tracy.ZoneInit("AssetManager GetFileIfExists", @src());
    defer zone.Deinit();

    return OpenFile(engine_context, rel_path, path_type) catch |err| {
        if (err == error.FileNotFound) {
            MarkAssetToDelete(entity_id);
        }
        return null;
    };
}

fn CheckModified(_: *AssetManager, file_stat: std.fs.File.Stat, last_modified: i128) bool {
    const zone = Tracy.ZoneInit("AssetManager CheckLastModified", @src());
    defer zone.Deinit();

    if (last_modified != file_stat.mtime) {
        return true;
    }
    return false;
}

fn ComputePathHash(path: []const u8) u64 {
    const zone = Tracy.ZoneInit("AssetManager ComputePathHas", @src());
    defer zone.Deinit();
    var hasher = std.hash.Fnv1a_64.init();
    hasher.update(path);
    return hasher.final();
}

fn CreateAssetFile(self: *AssetManager, engine_context: *EngineContext, file_source: FileSource) !AssetType {
    const zone = Tracy.ZoneInit("AssetManager CreateAssetFile", @src());
    defer zone.Deinit();

    const engine_allocator = engine_context.EngineAllocator();

    const new_asset_id = try self.mAssetECS.CreateEntity(engine_allocator);

    _ = try self.mAssetECS.AddComponent(engine_allocator, new_asset_id, AssetMetaData{ .mRefs = 0 });
    const file_meta_data = try self.mAssetECS.AddComponent(engine_allocator, new_asset_id, FileMetaData{
        .mLastModified = .zero,
        .mSize = 0,
        .mHash = 0,
        .mPathType = file_source.path_type,
    });

    _ = try file_meta_data.mRelPath.print(engine_allocator, "{s}", .{file_source.rel_path});

    const file = try self.OpenFile(engine_context, file_source.rel_path, file_source.path_type);
    defer self.CloseFile(engine_context.Io(), file);
    const fstats = try file.stat(engine_context.Io());

    try self.UpdateAsset(engine_context, new_asset_id, file, fstats);

    return new_asset_id;
}

fn CreateAssetGen(self: *AssetManager, engine_allocator: std.mem.Allocator) !AssetType {
    const zone = Tracy.ZoneInit("AssetManager CreateAssetGen", @src());
    defer zone.Deinit();

    const new_asset_id = try self.mAssetECS.CreateEntity(engine_allocator);

    _ = try self.mAssetECS.AddComponent(engine_allocator, new_asset_id, AssetMetaData{ .mRefs = 0 });
    _ = try self.mAssetECS.AddComponent(engine_allocator, new_asset_id, GenMetaData{});

    return new_asset_id;
}
fn DeleteAsset(self: *AssetManager, engine_allocator: std.mem.Allocator, asset_id: AssetType) !void {
    const zone = Tracy.ZoneInit("AssetManager DeleteAsset", @src());
    defer zone.Deinit();

    const file_data = self.mAssetECS.GetComponent(FileMetaData, asset_id).?;

    const path_hash = ComputePathHash(file_data.mRelPath.items);

    _ = switch (file_data.mPathType) {
        .Eng => self.mPathToIDEng.remove(path_hash),
        .Prj => self.mPathToIDPrj.remove(path_hash),
    };

    try self.mAssetECS.DestroyEntity(engine_allocator, asset_id);
}

fn MarkAssetToDelete(self: *AssetManager, asset_id: AssetType) void {
    const zone = Tracy.ZoneInit("AssetManager MarkAssetToDelete", @src());
    defer zone.Deinit();

    const file_meta_data = self.mAssetECS.GetComponent(FileMetaData, asset_id).?;
    file_meta_data.mLastModified = std.time.nanoTimestamp();
    file_meta_data.mSize = 0;
}

fn UpdateAsset(self: *AssetManager, engine_context: *EngineContext, asset_id: AssetType, file: std.Io.File, fstats: std.Io.File.Stat) !void {
    const zone = Tracy.ZoneInit("AssetManager UpdateAsset", @src());
    defer zone.Deinit();

    const file_data = self.mAssetECS.GetComponent(FileMetaData, asset_id).?;

    var file_hasher = std.hash.Fnv1a_64.init();
    var file_reader = file.reader(engine_context.Io(), &.{});
    const contents = try file_reader.interface.allocRemaining(engine_context.FrameAllocator(), std.Io.Limit.unlimited);
    file_hasher.update(contents);

    file_data.mHash = file_hasher.final();
    file_data.mLastModified = fstats.mtime;
    file_data.mSize = fstats.size;
}

fn CheckAssetForDeletion(self: *AssetManager, engine_context: *EngineContext, asset_id: AssetType) !void {
    const zone = Tracy.ZoneInit("AssetManager::CheckAssetForDelete", @src());
    defer zone.Deinit();

    //check to see if we can recover the asset
    if (try self.RetryAssetExists(engine_context, asset_id)) return;

    //if we cannot recover it automatically then delete it from AssetManager
    const file_data = self.mAssetECS.GetComponent(FileMetaData, asset_id).?;
    if (std.time.nanoTimestamp() - file_data.mLastModified > ASSET_DELETE_TIMEOUT_NS) {
        try self.DeleteAsset(engine_context.EngineAllocator(), asset_id);
    }
}

//This function checks again to see if we can open the file maybe there was
//some weird issue last frame but this frame the file is ok so we can recover it
fn RetryAssetExists(self: *AssetManager, engine_context: *EngineContext, asset_id: AssetType) !bool {
    const zone = Tracy.ZoneInit("AssetManager::RetryAssetExists", @src());
    defer zone.Deinit();
    const file_data = self.mAssetECS.GetComponent(FileMetaData, asset_id).?;

    const abs_path = try self.GetAbsPath(engine_context.FrameAllocator(), file_data.mRelPath.items, file_data.mPathType);

    const file = std.fs.openFileAbsolute(abs_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            return false;
        } else {
            return err;
        }
    };
    defer self.CloseFile(engine_context.Io(), file);

    const fstats = try file.stat();

    try self.UpdateAsset(engine_context, asset_id, file, fstats);

    return true;
}

fn _ValidateAssetType(asset_type: type) void {
    std.debug.assert(asset_type != FileMetaData);
    std.debug.assert(asset_type != AssetMetaData);
}

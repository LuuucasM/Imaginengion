const std = @import("std");
const GenUUID = @import("../Core/UUID.zig").GenUUID;
const Set = @import("../Vendor/ziglang-set/src/hash_set/managed.zig").HashSetManaged;

const Assets = @import("Assets.zig");
const AssetMetaData = Assets.AssetMetaData;
const FileMetaData = Assets.FileMetaData;
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

const PathType = FileMetaData.PathType;

const ASSET_DELETE_TIMEOUT_NS: i128 = 1_000_000_000;
const MAX_FILE_SIZE: usize = 4_000_000_000;

pub const AssetType = u32;

pub const ECSManagerAssets = ECSManager(AssetType, &AssetsList);

const InternalData = struct {
    DefaultFileMetaData: FileMetaData = .{},
    DefaultTexture2D: Texture2D = .{},
    DefaultTextAsset: TextAsset = .{},
    DefaultAudioAsset: AudioAsset = .{},
};
mAssetECS: ECSManagerAssets = undefined,
mPathToIDEng: std.AutoHashMap(u64, AssetType) = undefined,
mPathToIDPrj: std.AutoHashMap(u64, AssetType) = undefined,
mCWD: std.fs.Dir = undefined,
mCWDPath: std.ArrayList(u8) = .{},
mProjectDirectory: ?std.fs.Dir = undefined,
mProjectPath: std.ArrayList(u8) = .{},

_internal: InternalData = .{},

pub fn Init(self: *AssetManager, engine_context: *EngineContext) !void {
    const engine_allocator = engine_context.EngineAllocator();

    try self.mAssetECS.Init(engine_allocator);
    self.mPathToIDEng = std.AutoHashMap(u64, AssetType).init(engine_allocator);
    self.mPathToIDPrj = std.AutoHashMap(u64, AssetType).init(engine_allocator);
    self.mCWD = std.fs.cwd();

    var buffer: [260]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const fba_allocator = fba.allocator();

    const cwd_path = try std.fs.cwd().realpathAlloc(fba_allocator, ".");
    _ = try self.mCWDPath.writer(engine_allocator).write(cwd_path);
}

pub fn Setup(self: *AssetManager, engine_context: *EngineContext) !void {
    const frame_allocator = engine_context.FrameAllocator();

    //FILE META DATA =======================
    _ = try self._internal.DefaultFileMetaData.mRelPath.writer(engine_context.EngineAllocator()).write("default");

    //TEXTURE 2D =========================
    const texture2d_rel_path = "assets/textures/DefaultTexture.png";
    const texture2d_abs_path = try self.GetAbsPath(frame_allocator, texture2d_rel_path, .Eng);
    const texture2d_file = try std.fs.openFileAbsolute(texture2d_abs_path, .{});
    defer texture2d_file.close();
    try self._internal.DefaultTexture2D.Init(engine_context, texture2d_abs_path, texture2d_rel_path, texture2d_file);

    //TEXT ================================
    const text_rel_path = "assets/fonts/default/static/ChironGoRoundTC-Regular.ttf";
    const text_abs_path = try self.GetAbsPath(frame_allocator, text_rel_path, .Eng);
    const text_file = try std.fs.openFileAbsolute(text_abs_path, .{});
    defer text_file.close();
    try self._internal.DefaultTextAsset.Init(engine_context, text_abs_path, text_rel_path, text_file);

    //AUDIO =================================
    const audio_rel_path = "assets/sounds/DefaultSound.mp3";
    const audio_abs_path = try self.GetAbsPath(frame_allocator, audio_rel_path, .Eng);
    const audio_file = try std.fs.openFileAbsolute(audio_abs_path, .{});
    defer audio_file.close();
    try self._internal.DefaultAudioAsset.Init(engine_context, audio_abs_path, audio_rel_path, audio_file);
}

pub fn Deinit(self: *AssetManager, engine_context: *EngineContext) !void {
    try self._internal.DefaultTexture2D.Deinit(engine_context);
    try self._internal.DefaultTextAsset.Deinit(engine_context);
    try self._internal.DefaultAudioAsset.Deinit(engine_context);
    self._internal.DefaultFileMetaData.mRelPath.deinit(engine_context.EngineAllocator());

    try self.mAssetECS.Deinit(engine_context);

    self.mPathToIDEng.deinit();
    self.mPathToIDPrj.deinit();

    self.mCWD.close();

    if (self.mProjectDirectory) |*dir| {
        dir.close();
    }

    self.mCWDPath.deinit(engine_context.EngineAllocator());
    self.mProjectPath.deinit(engine_context.EngineAllocator());
}

pub fn GetAssetHandleRef(self: *AssetManager, engine_allocator: std.mem.Allocator, rel_path: []const u8, path_type: PathType) !AssetHandle {
    std.debug.assert(rel_path.len != 0);

    if (std.mem.eql(u8, rel_path, "default") and path_type == .Eng) {
        return AssetHandle{
            .mID = AssetHandle.NullHandle,
            .mAssetManager = self,
        };
    }

    const path_hash = ComputePathHash(rel_path);

    const entity_id = switch (path_type) {
        .Eng => self.mPathToIDEng.get(path_hash),
        .Prj => self.mPathToIDPrj.get(path_hash),
    };

    if (entity_id) |id| {
        self.mAssetECS.GetComponent(AssetMetaData, id).?.mRefs += 1;
        return AssetHandle{ .mID = id, .mAssetManager = self };
    } else {
        const asset_handle = try self.CreateAsset(engine_allocator, rel_path, path_type);
        self.mAssetECS.GetComponent(AssetMetaData, asset_handle.mID).?.mRefs += 1;
        _ = try switch (path_type) {
            .Eng => self.mPathToIDEng.put(path_hash, asset_handle.mID),
            .Prj => self.mPathToIDPrj.put(path_hash, asset_handle.mID),
        };
        return asset_handle;
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

    if (self.mAssetECS.IsActiveEntityID(asset_id)) {
        if (self.mAssetECS.GetComponent(asset_type, asset_id)) |asset| {
            return asset;
        } else {
            const file_data = self.mAssetECS.GetComponent(FileMetaData, asset_id).?;
            std.debug.assert(file_data.mRelPath.items.len > 0);

            const abs_path = try self.GetAbsPath(engine_context.FrameAllocator(), file_data.mRelPath.items, file_data.mPathType);

            const asset_file = try self.OpenFile(file_data.mRelPath.items, file_data.mPathType);
            defer self.CloseFile(asset_file);

            var asset_component = asset_type{};
            asset_component.Init(engine_context, abs_path, file_data.mRelPath.items, asset_file) catch |err| {
                if (err == error.AssetInitFailed) return try self.GetDefaultAsset(asset_type) else return err;
            };

            return self.mAssetECS.AddComponent(asset_type, asset_id, asset_component);
        }
    } else {
        return try self.GetDefaultAsset(asset_type);
    }
}

pub fn GetFileMetaData(self: *AssetManager, id: AssetType) *FileMetaData {
    if (self.mAssetECS.IsActiveEntityID(id)) {
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
                const file = try self.OpenFile(file_data.mRelPath.items, file_data.mPathType);
                try self.UpdateAsset(entity_id, file, file_stat);
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

pub fn OpenFile(self: *AssetManager, rel_path: []const u8, path_type: PathType) !std.fs.File {
    const zone = Tracy.ZoneInit("AssetManager OpenFile", @src());
    defer zone.Deinit();
    switch (path_type) {
        .Eng => return try self.mCWD.openFile(rel_path, .{}),
        .Prj => return try self.mProjectDirectory.?.openFile(rel_path, .{}),
    }
}

pub fn CloseFile(_: *AssetManager, file: std.fs.File) void {
    const zone = Tracy.ZoneInit("AssetManager CloseFile", @src());
    defer zone.Deinit();
    file.close();
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
    }
}

pub fn GetRelPath(self: *AssetManager, abs_path: []const u8) []const u8 {
    const zone = Tracy.ZoneInit("AssetManager GetRelPath", @src());
    defer zone.Deinit();
    return abs_path[self.mProjectPath.items.len + 1 ..];
}

pub fn ProcessDestroyedAssets(self: *AssetManager, engine_context: *EngineContext) !void {
    try self.mAssetECS.ProcessEvents(engine_context, .EC_RemoveObj);
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

fn GetFileIfExists(_: *AssetManager, rel_path: []const u8, path_type: PathType, entity_id: AssetType) !?std.fs.File {
    const zone = Tracy.ZoneInit("AssetManager GetFileIfExists", @src());
    defer zone.Deinit();

    return OpenFile(rel_path, path_type) catch |err| {
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

fn CreateAsset(self: *AssetManager, engine_allocator: std.mem.Allocator, rel_path: []const u8, path_type: PathType) !AssetHandle {
    const zone = Tracy.ZoneInit("AssetManager CreateAsset", @src());
    defer zone.Deinit();

    const new_handle = AssetHandle{
        .mID = try self.mAssetECS.CreateEntity(),
        .mAssetManager = self,
    };
    _ = try self.mAssetECS.AddComponent(AssetMetaData, new_handle.mID, .{
        .mRefs = 0,
    });
    const file_meta_data = try self.mAssetECS.AddComponent(FileMetaData, new_handle.mID, .{
        .mLastModified = 0,
        .mSize = 0,
        .mHash = 0,
        .mPathType = path_type,
    });

    _ = try file_meta_data.mRelPath.writer(engine_allocator).write(rel_path);

    const file = try self.OpenFile(rel_path, path_type);
    defer self.CloseFile(file);
    const fstats = try file.stat();

    try self.UpdateAsset(new_handle.mID, file, fstats);

    return new_handle;
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

fn UpdateAsset(self: *AssetManager, asset_id: AssetType, file: std.fs.File, fstats: std.fs.File.Stat) !void {
    const zone = Tracy.ZoneInit("AssetManager UpdateAsset", @src());
    defer zone.Deinit();

    const file_data = self.mAssetECS.GetComponent(FileMetaData, asset_id).?;

    var file_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer file_arena.deinit();
    const arena_allocator = file_arena.allocator();

    var file_hasher = std.hash.Fnv1a_64.init();
    file_hasher.update(try file.readToEndAlloc(arena_allocator, MAX_FILE_SIZE));

    file_data.mHash = file_hasher.final();
    file_data.mLastModified = fstats.mtime;
    file_data.mSize = fstats.size;
}

fn CheckAssetForDeletion(self: *AssetManager, engine_context: *EngineContext, asset_id: AssetType) !void {
    const zone = Tracy.ZoneInit("AssetManager::CheckAssetForDelete", @src());
    defer zone.Deinit();

    //check to see if we can recover the asset
    if (try self.RetryAssetExists(engine_context.FrameAllocator(), asset_id)) return;

    //if we cannot recover it automatically then delete it from AssetManager
    const file_data = self.mAssetECS.GetComponent(FileMetaData, asset_id).?;
    if (std.time.nanoTimestamp() - file_data.mLastModified > ASSET_DELETE_TIMEOUT_NS) {
        try self.DeleteAsset(engine_context.EngineAllocator(), asset_id);
    }
}

//This function checks again to see if we can open the file maybe there was
//some weird issue last frame but this frame the file is ok so we can recover it
fn RetryAssetExists(self: *AssetManager, frame_allocator: std.mem.Allocator, asset_id: AssetType) !bool {
    const zone = Tracy.ZoneInit("AssetManager::RetryAssetExists", @src());
    defer zone.Deinit();
    const file_data = self.mAssetECS.GetComponent(FileMetaData, asset_id).?;

    const abs_path = try self.GetAbsPath(frame_allocator, file_data.mRelPath.items, file_data.mPathType);

    const file = std.fs.openFileAbsolute(abs_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            return false;
        } else {
            return err;
        }
    };
    defer self.CloseFile(file);

    const fstats = try file.stat();

    try self.UpdateAsset(asset_id, file, fstats);

    return true;
}

inline fn _ValidateAssetType(asset_type: type) void {
    std.debug.assert(asset_type != FileMetaData);
    std.debug.assert(asset_type != AssetMetaData);
}

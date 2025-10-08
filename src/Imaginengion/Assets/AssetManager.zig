const std = @import("std");
const GenUUID = @import("../Core/UUID.zig").GenUUID;
const Set = @import("../Vendor/ziglang-set/src/hash_set/managed.zig").HashSetManaged;
const Assets = @import("Assets.zig");
const AssetMetaData = Assets.AssetMetaData;
const FileMetaData = Assets.FileMetaData;
const ScriptAsset = Assets.ScriptAsset;
const TextAsset = Assets.TextAsset;
const AssetsList = Assets.AssetsList;
const AssetHandle = @import("AssetHandle.zig");
const ArraySet = @import("../Vendor/ziglang-set/src/array_hash_set/managed.zig").ArraySetManaged;
const ECSManager = @import("../ECS/ECSManager.zig").ECSManager;
const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;

const Tracy = @import("../Core/Tracy.zig");

const AssetManager = @This();

const PathType = FileMetaData.PathType;

const ASSET_DELETE_TIMEOUT_NS: i128 = 1_000_000_000;
const MAX_FILE_SIZE: usize = 4_000_000_000;

var AssetM: AssetManager = AssetManager{};
var AssetGPA = std.heap.DebugAllocator(.{}).init;
const AssetAllocator = AssetGPA.allocator();

pub const AssetType = u32;

pub const ECSManagerAssets = ECSManager(AssetType, &AssetsList);

mAssetECS: ECSManagerAssets = undefined,
mPathToIDEng: std.AutoHashMap(u64, AssetType) = undefined,
mPathToIDPrj: std.AutoHashMap(u64, AssetType) = undefined,
mCWD: std.fs.Dir = undefined,
mCWDPath: std.ArrayList(u8) = undefined,
mProjectDirectory: ?std.fs.Dir = undefined,
mProjectPath: std.ArrayList(u8) = undefined,

pub fn Init() !void {
    AssetM = AssetManager{
        .mAssetECS = try ECSManagerAssets.Init(AssetAllocator),
        .mPathToIDEng = std.AutoHashMap(u64, AssetType).init(AssetAllocator),
        .mPathToIDPrj = std.AutoHashMap(u64, AssetType).init(AssetAllocator),
        .mCWD = std.fs.cwd(),
        .mCWDPath = std.ArrayList(u8){},
        .mProjectPath = std.ArrayList(u8){},
    };

    var buffer: [260]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const fba_allocator = fba.allocator();

    const cwd_path = try std.fs.cwd().realpathAlloc(fba_allocator, ".");
    _ = try AssetM.mCWDPath.writer(AssetAllocator).write(cwd_path);
}

pub fn Deinit() !void {
    try AssetM.mAssetECS.Deinit();
    AssetM.mPathToIDEng.deinit();
    AssetM.mPathToIDPrj.deinit();
    AssetM.mCWD.close();
    if (AssetM.mProjectDirectory) |*dir| {
        dir.close();
    }
    AssetM.mCWDPath.deinit(AssetAllocator);
    AssetM.mProjectPath.deinit(AssetAllocator);

    _ = AssetGPA.deinit();
}

pub fn GetAssetHandleRef(rel_path: []const u8, path_type: PathType) !AssetHandle {
    std.debug.assert(rel_path.len != 0);

    const path_hash = ComputePathHash(rel_path);

    const entity_id = switch (path_type) {
        .Eng => AssetM.mPathToIDEng.get(path_hash),
        .Prj => AssetM.mPathToIDPrj.get(path_hash),
    };

    if (entity_id) |id| {
        AssetM.mAssetECS.GetComponent(AssetMetaData, id).?.mRefs += 1;
        return AssetHandle{
            .mID = id,
        };
    } else {
        const asset_handle = try CreateAsset(rel_path, path_type);
        AssetM.mAssetECS.GetComponent(AssetMetaData, asset_handle.mID).?.mRefs += 1;
        _ = try switch (path_type) {
            .Eng => AssetM.mPathToIDEng.put(path_hash, asset_handle.mID),
            .Prj => AssetM.mPathToIDPrj.put(path_hash, asset_handle.mID),
        };
        return asset_handle;
    }
}

pub fn ReleaseAssetHandleRef(asset_handle: *AssetHandle) void {
    if (AssetM.mAssetECS.GetComponent(AssetMetaData, asset_handle.mID)) |meta_data| {
        meta_data.mRefs -= 1;
    }
    asset_handle.mID = AssetHandle.NullHandle;
}

pub fn GetAsset(comptime asset_type: type, asset_id: AssetType) !*asset_type {
    const zone = Tracy.ZoneInit("AssetManager GetAsset", @src());
    defer zone.Deinit();

    //checking the asset type will be evaluated at comptime which will determine which branch
    //the function body will contain so it doesnt get processed in runtime
    //and it is needed because the "meta" asset types dont have an Init(because they are not being)
    //loaded from disk just meta data) so this lets it compile correct

    if (asset_type == FileMetaData or asset_type == AssetMetaData) {
        return AssetM.mAssetECS.GetComponent(asset_type, asset_id).?;
    } else {
        if (AssetM.mAssetECS.GetComponent(asset_type, asset_id)) |asset| {
            return asset;
        } else {
            const file_data = AssetM.mAssetECS.GetComponent(FileMetaData, asset_id).?;

            var buffer: [260 * 2]u8 = undefined;
            var fba = std.heap.FixedBufferAllocator.init(&buffer);
            const fba_allocator = fba.allocator();

            const abs_path = try GetAbsPath(file_data.mRelPath.items, file_data.mPathType, fba_allocator);

            const asset_file = try OpenFile(file_data.mRelPath.items, file_data.mPathType);
            defer CloseFile(asset_file);

            const new_asset = try asset_type.Init(AssetAllocator, abs_path, file_data.mRelPath.items, asset_file);

            return try AssetM.mAssetECS.AddComponent(asset_type, asset_id, new_asset);
        }
    }
}

pub fn OnUpdate(frame_allocator: std.mem.Allocator) !void {
    const zone = Tracy.ZoneInit("AssetManager OnUpdate", @src());
    defer zone.Deinit();

    const group = try AssetM.mAssetECS.GetGroup(GroupQuery{ .Component = FileMetaData }, frame_allocator);
    for (group.items) |entity_id| {
        const file_data = AssetM.mAssetECS.GetComponent(FileMetaData, entity_id).?;
        if (file_data.mSize == 0) {
            try CheckAssetForDeletion(entity_id);
            continue;
        }
        //then check if the asset path is still valid
        if (try GetFileStatsIfExists(file_data.mRelPath.items, file_data.mPathType, entity_id)) |file_stat| {

            //check to see if the file needs to be updated
            if (CheckModified(file_stat, file_data.mLastModified)) {
                const file = try OpenFile(file_data.mRelPath.items, file_data.mPathType);
                try UpdateAsset(entity_id, file, file_stat);
            }
        }
    }
}

pub fn GetGroup(comptime query: GroupQuery, frame_allocator: std.mem.Allocator) !std.ArrayList(AssetType) {
    return try AssetM.mAssetECS.GetGroup(query, frame_allocator);
}

pub fn OnNewProjectEvent(abs_path: []const u8) !void {
    if (AssetM.mProjectDirectory) |*dir| {
        dir.close();
        AssetM.mProjectDirectory = null;
    }

    AssetM.mProjectPath.clearAndFree(AssetAllocator);

    AssetM.mProjectDirectory = try std.fs.openDirAbsolute(abs_path, .{});

    _ = try AssetM.mProjectPath.writer(AssetAllocator).write(abs_path);
}

pub fn OnOpenProjectEvent(abs_path: []const u8) !void {
    if (AssetM.mProjectDirectory) |*dir| {
        dir.close();
        AssetM.mProjectDirectory = null;
    }

    AssetM.mProjectPath.clearAndFree(AssetAllocator);

    const dir_name = std.fs.path.dirname(abs_path).?;

    AssetM.mProjectDirectory = try std.fs.openDirAbsolute(dir_name, .{});

    _ = try AssetM.mProjectPath.writer(AssetAllocator).write(dir_name);
}

pub fn OpenFileStats(rel_path: []const u8, path_type: PathType) !std.fs.File.Stat {
    const zone = Tracy.ZoneInit("AssetManager OpenFileStats", @src());
    defer zone.Deinit();

    switch (path_type) {
        .Eng => return try AssetM.mCWD.statFile(rel_path),
        .Prj => return try AssetM.mProjectDirectory.?.statFile(rel_path),
    }
}

pub fn OpenFile(rel_path: []const u8, path_type: PathType) !std.fs.File {
    const zone = Tracy.ZoneInit("AssetManager OpenFile", @src());
    defer zone.Deinit();
    switch (path_type) {
        .Eng => return try AssetM.mCWD.openFile(rel_path, .{}),
        .Prj => return try AssetM.mProjectDirectory.?.openFile(rel_path, .{}),
    }
}

pub fn CloseFile(file: std.fs.File) void {
    const zone = Tracy.ZoneInit("AssetManager CloseFile", @src());
    defer zone.Deinit();
    file.close();
}

pub fn GetFileStats(file: std.fs.File) !std.fs.File.Stat {
    const zone = Tracy.ZoneInit("AssetManager GetFileStats", @src());
    defer zone.Deinit();
    return file.stat();
}

pub fn GetAbsPath(rel_path: []const u8, path_type: PathType, allocator: std.mem.Allocator) ![]const u8 {
    const zone = Tracy.ZoneInit("AssetManager GetAbsPath", @src());
    defer zone.Deinit();

    switch (path_type) {
        .Eng => {
            return try std.fs.path.join(allocator, &[_][]const u8{ AssetM.mCWDPath.items, rel_path });
        },
        .Prj => {
            return try std.fs.path.join(allocator, &[_][]const u8{ AssetM.mProjectPath.items, rel_path });
        },
    }
}

pub fn GetRelPath(abs_path: []const u8) []const u8 {
    const zone = Tracy.ZoneInit("AssetManager GetRelPath", @src());
    defer zone.Deinit();
    return abs_path[AssetM.mProjectPath.items.len + 1 ..];
}

pub fn ProcessDestroyedAssets() !void {
    try AssetM.mAssetECS.ProcessEvents(.EC_RemoveObj);
}

fn GetFileStatsIfExists(rel_path: []const u8, path_type: PathType, entity_id: AssetType) !?std.fs.File.Stat {
    const zone = Tracy.ZoneInit("AssetManager GetFileStatsIfExists", @src());
    defer zone.Deinit();

    return OpenFileStats(rel_path, path_type) catch |err| {
        if (err == error.FileNotFound) {
            MarkAssetToDelete(entity_id);
            return null;
        }
        return null;
    };
}

fn GetFileIfExists(rel_path: []const u8, path_type: PathType, entity_id: AssetType) !?std.fs.File {
    const zone = Tracy.ZoneInit("AssetManager GetFileIfExists", @src());
    defer zone.Deinit();

    return OpenFile(rel_path, path_type) catch |err| {
        if (err == error.FileNotFound) {
            MarkAssetToDelete(entity_id);
        }
        return null;
    };
}

fn CheckModified(file_stat: std.fs.File.Stat, last_modified: i128) bool {
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

fn CreateAsset(rel_path: []const u8, path_type: PathType) !AssetHandle {
    const zone = Tracy.ZoneInit("AssetManager CreateAsset", @src());
    defer zone.Deinit();

    const new_handle = AssetHandle{
        .mID = try AssetM.mAssetECS.CreateEntity(),
    };
    _ = try AssetM.mAssetECS.AddComponent(AssetMetaData, new_handle.mID, .{
        .mRefs = 0,
    });
    const file_meta_data = try AssetM.mAssetECS.AddComponent(FileMetaData, new_handle.mID, .{
        .mLastModified = 0,
        .mSize = 0,
        .mHash = 0,
        .mPathType = path_type,

        ._PathAllocator = AssetAllocator,
    });

    _ = try file_meta_data.mRelPath.writer(file_meta_data._PathAllocator).write(rel_path);

    const file = try OpenFile(rel_path, path_type);
    defer CloseFile(file);
    const fstats = try file.stat();

    try UpdateAsset(new_handle.mID, file, fstats);

    return new_handle;
}

fn DeleteAsset(asset_id: AssetType) !void {
    const zone = Tracy.ZoneInit("AssetManager DeleteAsset", @src());
    defer zone.Deinit();

    const file_data = AssetM.mAssetECS.GetComponent(FileMetaData, asset_id).?;

    const path_hash = ComputePathHash(file_data.mRelPath.items);

    _ = switch (file_data.mPathType) {
        .Eng => AssetM.mPathToIDEng.remove(path_hash),
        .Prj => AssetM.mPathToIDPrj.remove(path_hash),
    };

    try AssetM.mAssetECS.DestroyEntity(asset_id);
}

fn MarkAssetToDelete(asset_id: AssetType) void {
    const zone = Tracy.ZoneInit("AssetManager MarkAssetToDelete", @src());
    defer zone.Deinit();

    const file_meta_data = AssetM.mAssetECS.GetComponent(FileMetaData, asset_id).?;
    file_meta_data.mLastModified = std.time.nanoTimestamp();
    file_meta_data.mSize = 0;
}

fn UpdateAsset(asset_id: AssetType, file: std.fs.File, fstats: std.fs.File.Stat) !void {
    const zone = Tracy.ZoneInit("AssetManager UpdateAsset", @src());
    defer zone.Deinit();

    const file_data = AssetM.mAssetECS.GetComponent(FileMetaData, asset_id).?;

    var file_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer file_arena.deinit();
    const arena_allocator = file_arena.allocator();

    var file_hasher = std.hash.Fnv1a_64.init();
    file_hasher.update(try file.readToEndAlloc(arena_allocator, MAX_FILE_SIZE));

    file_data.mHash = file_hasher.final();
    file_data.mLastModified = fstats.mtime;
    file_data.mSize = fstats.size;
}

fn CheckAssetForDeletion(asset_id: AssetType) !void {
    const zone = Tracy.ZoneInit("AssetManager CheckAssetForDelete", @src());
    defer zone.Deinit();

    //check to see if we can recover the asset
    if (try RetryAssetExists(asset_id)) return;

    //if its run out of time then just delete
    const file_data = AssetM.mAssetECS.GetComponent(FileMetaData, asset_id).?;
    if (std.time.nanoTimestamp() - file_data.mLastModified > ASSET_DELETE_TIMEOUT_NS) {
        try DeleteAsset(asset_id);
    }
}

//This function checks again to see if we can open the file maybe there was
//some weird issue last frame but this frame the file is ok so we can recover it
fn RetryAssetExists(asset_id: AssetType) !bool {
    const zone = Tracy.ZoneInit("AssetManager RetryAssetExists", @src());
    defer zone.Deinit();
    const file_data = AssetM.mAssetECS.GetComponent(FileMetaData, asset_id).?;

    var buffer: [260]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const fba_allocator = fba.allocator();

    const abs_path = try GetAbsPath(file_data.mRelPath.items, file_data.mPathType, fba_allocator);

    const file = std.fs.openFileAbsolute(abs_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            return false;
        } else {
            return err;
        }
    };
    defer CloseFile(file);

    const fstats = try file.stat();

    try UpdateAsset(asset_id, file, fstats);

    return true;
}

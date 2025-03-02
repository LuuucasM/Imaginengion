const std = @import("std");
const GenUUID = @import("../Core/UUID.zig").GenUUID;
const Set = @import("../Vendor/ziglang-set/src/hash_set/managed.zig").HashSetManaged;
const Assets = @import("Assets.zig");
const AssetMetaData = Assets.AssetMetaData;
const FileMetaData = Assets.FileMetaData;
const IDComponent = Assets.IDComponent;
const AssetsList = Assets.AssetsList;
const AssetHandle = @import("AssetHandle.zig");
const ArraySet = @import("../Vendor/ziglang-set/src/array_hash_set/managed.zig").ArraySetManaged;
const ECSManager = @import("../ECS/ECSManager.zig");
const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;

const AssetManager = @This();

const ASSET_DELETE_TIMEOUT_NS: i128 = 1_000_000_000;
const MAX_FILE_SIZE: usize = 4_000_000_000;

var AssetM: AssetManager = AssetManager{};
var AssetGPA = std.heap.DebugAllocator(.{}).init;
var AssetMemoryPool = std.heap.ArenaAllocator.init(std.heap.page_allocator);

mAssetECS: ECSManager = undefined,
mAssetPathToID: std.AutoHashMap(u64, u32) = undefined,

pub fn Init() !void {
    AssetM = AssetManager{
        .mAssetECS = try ECSManager.Init(AssetGPA.allocator(), &AssetsList),
        .mAssetPathToID = std.AutoHashMap(u64, u32).init(AssetGPA.allocator()),
    };
}

pub fn Deinit() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const group = try AssetM.mAssetECS.GetGroup(GroupQuery{ .Component = FileMetaData }, allocator);

    for (group.items) |entity_id| {
        const file_data = AssetM.mAssetECS.GetComponent(FileMetaData, entity_id);
        AssetGPA.allocator().free(file_data.mAbsPath);
    }

    AssetM.mAssetECS.Deinit();
    AssetM.mAssetPathToID.deinit();
}

pub fn GetAssetHandleRef(abs_path: []const u8) !AssetHandle {
    std.debug.assert(abs_path.len != 0);

    const path_hash = ComputePathHash(abs_path);

    if (AssetM.mAssetPathToID.get(path_hash)) |entity_id| {
        AssetM.mAssetECS.GetComponent(AssetMetaData, entity_id).mRefs += 1;
        return AssetHandle{
            .mID = entity_id,
        };
    } else {
        const asset_handle = try CreateAsset(abs_path);
        AssetM.mAssetECS.GetComponent(AssetMetaData, asset_handle.mID).mRefs += 1;
        try AssetM.mAssetPathToID.put(path_hash, asset_handle.mID);
        return asset_handle;
    }
}

pub fn ReleaseAssetHandleRef(asset_id: u32) void {
    const asset_meta_data = AssetM.mAssetECS.GetComponent(AssetMetaData, asset_id);
    asset_meta_data.mRefs -= 1;
}

pub fn GetAsset(comptime asset_type: type, asset_id: u32) !*asset_type {
    const is_meta_component = asset_type == FileMetaData or asset_type == AssetMetaData or asset_type == IDComponent;
    if (is_meta_component) {
        return AssetM.mAssetECS.GetComponent(asset_type, asset_id);
    } else if (AssetM.mAssetECS.HasComponent(asset_type, asset_id)) {
        return AssetM.mAssetECS.GetComponent(asset_type, asset_id);
    } else {
        const file_data = AssetM.mAssetECS.GetComponent(FileMetaData, asset_id);
        const new_asset: asset_type = try asset_type.Init(file_data.mAbsPath);
        return try AssetM.mAssetECS.AddComponent(asset_type, asset_id, new_asset);
    }
}

pub fn OnUpdate() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const group = try AssetM.mAssetECS.GetGroup(GroupQuery{ .Component = FileMetaData }, allocator);
    for (group.items) |entity_id| {
        const file_data = AssetM.mAssetECS.GetComponent(FileMetaData, entity_id);
        if (file_data.mSize == 0) {
            try CheckAssetForDeletion(entity_id);
            continue;
        }
        //then check if the asset path is still valid
        if (try GetFileIfExists(file_data.mAbsPath, entity_id)) |file| {
            defer file.close();

            //check to see if the file needs to be updated
            CheckLastModified(file, file_data.mLastModified, entity_id);
        }
    }

    AssetM.mAssetECS.ProcessDestroyedEntities();
}

pub fn GetGroup(comptime query: GroupQuery, allocator: std.mem.Allocator) !std.ArrayList(u32) {
    return try AssetM.mAssetECS.GetGroup(query, allocator);
}

fn GetFileIfExists(path: []const u8, entity_id: u32) !?std.fs.File {
    return std.fs.cwd().openFile(path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            MarkAssetToDelete(entity_id);
            return null;
        } else {
            return err;
        }
    };
}

fn CheckLastModified(file: std.fs.File, last_modified: i128, entity_id: u32) void {
    const fstats = try file.stat();
    if (last_modified != fstats.mtime) {
        try UpdateAsset(entity_id, file, fstats);
    }
}

fn ComputePathHash(path: []const u8) u64 {
    var hasher = std.hash.Fnv1a_64.init();
    hasher.update(path);
    return hasher.final();
}

fn CreateAsset(abs_path: []const u8) !AssetHandle {
    std.debug.assert(abs_path.len != 0);

    const new_handle = AssetHandle{
        .mID = try AssetM.mAssetECS.CreateEntity(),
    };
    _ = try AssetM.mAssetECS.AddComponent(AssetMetaData, new_handle.mID, .{
        .mRefs = 0,
    });

    _ = try AssetM.mAssetECS.AddComponent(FileMetaData, new_handle.mID, .{
        .mAbsPath = try AssetGPA.allocator().dupe(u8, abs_path),
        .mLastModified = 0,
        .mSize = 0,
        .mHash = 0,
    });

    _ = try AssetM.mAssetECS.AddComponent(IDComponent, new_handle.mID, .{
        .ID = try GenUUID(),
    });

    const file = try std.fs.cwd().openFile(abs_path, .{});
    defer file.close();
    const fstats = try file.stat();

    try UpdateAsset(new_handle.mID, file, fstats);

    return new_handle;
}

fn DeleteAsset(asset_id: u32) !void {
    const file_data = AssetM.mAssetECS.GetComponent(FileMetaData, asset_id);
    const path_hash = ComputePathHash(file_data.mAbsPath);
    _ = AssetM.mAssetPathToID.remove(path_hash);
    AssetGPA.allocator().free(file_data.mAbsPath);
    try AssetM.mAssetECS.DestroyEntity(asset_id);
}

fn MarkAssetToDelete(asset_id: u32) void {
    const file_meta_data = AssetM.mAssetECS.GetComponent(FileMetaData, asset_id);
    file_meta_data.mLastModified = std.time.nanoTimestamp();
    file_meta_data.mSize = 0;
}

fn UpdateAsset(asset_id: u32, file: std.fs.File, fstats: std.fs.File.Stat) !void {
    const file_data = AssetM.mAssetECS.GetComponent(FileMetaData, asset_id);

    var file_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer file_arena.deinit();
    const allocator = file_arena.allocator();

    var file_hasher = std.hash.Fnv1a_64.init();
    file_hasher.update(try file.readToEndAlloc(allocator, MAX_FILE_SIZE));

    file_data.mHash = file_hasher.final();
    file_data.mLastModified = fstats.mtime;
    file_data.mSize = fstats.size;
}

fn CheckAssetForDeletion(asset_id: u32) !void {
    //check to see if we can recover the asset
    if (try RetryAssetExists(asset_id)) return;

    //if its run out of time then just delete
    const file_data = AssetM.mAssetECS.GetComponent(FileMetaData, asset_id);
    if (std.time.nanoTimestamp() - file_data.mLastModified > ASSET_DELETE_TIMEOUT_NS) {
        try DeleteAsset(asset_id);
    }
}

//This function checks again to see if we can open the file maybe there was
//some weird issue last frame but this frame the file is ok so we can recover it
fn RetryAssetExists(asset_id: u32) !bool {
    const file_data = AssetM.mAssetECS.GetComponent(FileMetaData, asset_id);
    const file = std.fs.openFileAbsolute(file_data.mAbsPath, .{}) catch |err| {
        if (err == error.FileNotFound) {
            return false;
        } else {
            return err;
        }
    };
    defer file.close();

    const fstats = try file.stat();

    try UpdateAsset(asset_id, file, fstats);

    return true;
}

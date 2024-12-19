const std = @import("std");
const GenUUID = @import("../Core/UUID.zig").GenUUID;
const Asset = @import("Asset.zig");
const AssetHandle = Asset.AssetHandle;
const Set = @import("../Vendor/ziglang-set/src/hash_set/managed.zig").HashSetManaged;
const AssetMetaData = @import("./Assets/AssetMetaData.zig");
const FileMetaData = @import("./Assets/FileMetaData.zig");
const IDComponent = @import("./Assets/IDComponent.zig");
const AssetsList = @import("Assets.zig").AssetsList;
const ECSManager = @import("../ECS/ECSManager.zig");

const AssetManager = @This();

const ASSET_DELETE_TIMEOUT_NS: i128 = 1_000_000_000;
const MAX_FILE_SIZE: usize = 4_000_000_000;

var AssetM: *AssetManager = undefined;

mEngineAllocator: std.mem.Allocator,
mAssetGPA: std.heap.GeneralPurposeAllocator(.{}),
mAssetIDToAsset: std.AutoHashMap(u32, Asset),
mAssetECS: ECSManager,
mAssetMemoryPool: std.heap.ArenaAllocator,
mAssetPathToID: std.StringHashMap(u32),
//note the head of the list is most recently used and tail is lease
mAssetGPUCache: std.DoublyLinkedList(Asset),
mAssetCPUCache: std.DoublyLinkedList(Asset),

pub fn Init(EngineAllocator: std.mem.Allocator) !void {
    AssetM = try EngineAllocator.create(AssetManager);
    AssetM.* = .{
        .mEngineAllocator = EngineAllocator,
        .mAssetGPA = std.heap.GeneralPurposeAllocator(.{}){},
        .mAssetIDToAsset = std.AutoHashMap(u32, Asset).init(AssetM.mAssetGPA.allocator()),
        .mAssetECS = try ECSManager.Init(AssetM.mAssetGPA.allocator(), &AssetsList),
        .mAssetMemoryPool = std.heap.ArenaAllocator.init(std.heap.page_allocator),
        .mAssetPathToID = std.StringHashMap(u32).init(AssetM.mAssetGPA.allocator()),
    };
}

pub fn Deinit() void {
    AssetM.mAssetIDToAsset.deinit();
    AssetM.mAssetECS.Deinit();
    AssetM.mAssetMemoryPool.deinit();
    AssetM.mAssetPathToID.deinit();
    _ = AssetM.mAssetGPA.deinit();
    AssetM.mEngineAllocator.destroy(AssetM);
}

pub fn GetAssetHandleRef(abs_path: []const u8) AssetHandle {
    if (AssetM.mAssetPathToID.get(abs_path)) |entity_id| {
        AssetM.mAssetECS.GetComponent(AssetMetaData, entity_id).mRefs += 1;
        return AssetHandle{
            .mID = entity_id,
            .mECSRef = &AssetM.mAssetECS,
        };
    } else {
        const asset_handle = CreateAsset(abs_path);
        AssetM.mAssetPathToID.put(abs_path, asset_handle.mID);
        return asset_handle;
    }
}

pub fn ReleaseAssetHandleRef(asset_id: u32) void {
    const asset_meta_data = AssetM.mAssetECS.GetComponent(AssetMetaData, asset_id).mRefs;
    asset_meta_data.mRefs -= 1;
    if (asset_meta_data.mRefs == 0) {
        SetAssetToDelete(asset_id);
    }
}

pub fn GetAsset(comptime asset_type: type, asset_id: u32) asset_type {
    return AssetM.mAssetECS.GetOrAddComponent(asset_type, asset_id);
}

pub fn OnUpdate() !void {
    var iter = AssetM.mAssetIDToAsset.iterator();

    while (iter.next()) |entry| {
        const asset = entry.value_ptr;

        //first check to see if this asset will just get deleted
        if (asset.mSize == 0) {
            try CheckAssetToDelete(asset);
            continue;
        }

        //then check if the asset path is still valid
        const file = std.fs.openFileAbsolute(asset.mAbsPath, .{}) catch |err| {
            if (err == error.FileNotFound) {
                SetAssetToDelete(asset);
                continue;
            } else {
                return err;
            }
        };
        defer file.close();

        //then check if the asset needs to be updated
        const fstats = try file.stat();
        if (asset.mLastModified != fstats.mtime) {
            try UpdateAsset(asset, file, fstats);
        }
    }
}

pub fn GetHandleMap() std.AutoHashMap(u32, Asset) {
    return AssetM.mAssetIDToAsset;
}

fn CreateAsset(abs_path: []const u8) AssetHandle {
    const new_handle = AssetHandle{
        .mID = AssetM.mAssetECS.CreateEntity(),
        .ECSRef = &AssetM.mAssetECS,
    };
    AssetM.mAssetECS.AddComponent(AssetMetaData, new_handle.mID, .{
        .mAssetType = .None,
        .mRefs = 1,
    });

    const file = std.fs.openFileAbsolute(abs_path, .{}) catch |err| {
        return err;
    };
    defer file.close();
    const fstats = try file.stat();

    var file_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer file_arena.deinit();
    const allocator = file_arena.allocator();
    var file_hasher = std.hash.Fnv1a_64.init();
    file_hasher.update(try file.readToEndAlloc(allocator, MAX_FILE_SIZE));

    AssetM.mAssetECS.AddComponent(FileMetaData, new_handle.mID, .{
        .mAbsPath = AssetM.mAssetGPA.allocator().dupe([]const u8, abs_path),
        .mLastModified = fstats.mtime,
        .mSize = fstats.size,
        .mHash = file_hasher.final(),
    });

    AssetM.mAssetECS.AddComponent(IDComponent, new_handle.mID, .{
        .ID = GenUUID(),
    });

    return new_handle;
}

fn DeleteAsset(asset: *Asset) void {
    AssetM.mAssetGPA.allocator().free(asset.mAbsPath);
    _ = AssetM.mAssetIDToAsset.remove(asset.mAssetHandle.mID);
}

fn SetAssetToDelete(asset_id: u32) void {
    const file_meta_data = AssetM.mAssetECS.GetComponent(FileMetaData, asset_id);
    file_meta_data.mLastModified = std.time.nanoTimestamp();
    file_meta_data.mSize = 0;
}

fn UpdateAsset(asset: *Asset, file: std.fs.File, fstats: std.fs.File.Stat) !void {
    var file_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer file_arena.deinit();
    const allocator = file_arena.allocator();
    var file_hasher = std.hash.Fnv1a_64.init();
    file_hasher.update(try file.readToEndAlloc(allocator, MAX_FILE_SIZE));

    asset.mHash = file_hasher.final();
    asset.mLastModified = fstats.mtime;
    asset.mSize = fstats.size;
}

fn CheckAssetToDelete(asset: *Asset) !void {
    //check to see if we can recover the asset
    if (try RetryAssetExists(asset)) return;

    //if its run out of time then just delete
    if (std.time.nanoTimestamp() - asset.mLastModified > ASSET_DELETE_TIMEOUT_NS) {
        DeleteAsset(asset);
    }
}

//This function checks again to see if we can open the file maybe there was
//some weird issue last frame but this frame the file is ok so we can recover it
fn RetryAssetExists(asset: *Asset) !bool {
    const file = std.fs.openFileAbsolute(asset.mAbsPath, .{}) catch |err| {
        if (err == error.FileNotFound) {
            return false;
        } else {
            return err;
        }
    };
    defer file.close();

    const fstats = try file.stat();

    try UpdateAsset(asset, file, fstats);

    return true;
}

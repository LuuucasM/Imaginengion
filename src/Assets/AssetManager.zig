const std = @import("std");
const GenUUID = @import("../Core/UUID.zig").GenUUID;
const Set = @import("../Vendor/ziglang-set/src/hash_set/managed.zig").HashSetManaged;
const AssetMetaData = @import("./Assets/AssetMetaData.zig");
const FileMetaData = @import("./Assets/FileMetaData.zig");
const IDComponent = @import("./Assets/IDComponent.zig");
const AssetsList = @import("Assets.zig").AssetsList;
const AssetHandle = @import("AssetHandle.zig");
const ArraySet = @import("../Vendor/ziglang-set/src/array_hash_set/managed.zig").ArraySetManaged;
const ECSManager = @import("../ECS/ECSManager.zig");

const AssetManager = @This();

const ASSET_DELETE_TIMEOUT_NS: i128 = 1_000_000_000;
const MAX_FILE_SIZE: usize = 4_000_000_000;

var AssetM: *AssetManager = undefined;

mEngineAllocator: std.mem.Allocator,
mAssetGPA: std.heap.GeneralPurposeAllocator(.{}),
mAssetECS: ECSManager,
mAssetMemoryPool: std.heap.ArenaAllocator,
mAssetPathToID: std.StringHashMap(u32),

//note the head of the list is most recently used and tail is lease
mAssetGPUCache: std.DoublyLinkedList(u32),
mAssetCPUCache: std.DoublyLinkedList(u32),

pub fn Init(EngineAllocator: std.mem.Allocator) !void {
    AssetM = try EngineAllocator.create(AssetManager);
    AssetM.* = .{
        .mEngineAllocator = EngineAllocator,
        .mAssetGPA = std.heap.GeneralPurposeAllocator(.{}){},
        .mAssetECS = try ECSManager.Init(AssetM.mAssetGPA.allocator(), &AssetsList),
        .mAssetMemoryPool = std.heap.ArenaAllocator.init(std.heap.page_allocator),
        .mAssetPathToID = std.StringHashMap(u32).init(AssetM.mAssetGPA.allocator()),
        .mAssetCPUCache = std.DoublyLinkedList(u32){},
        .mAssetGPUCache = std.DoublyLinkedList(u32){},
    };
}

pub fn Deinit() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var group = try GetGroup(&[_]type{FileMetaData}, arena.allocator());
    var iter = group.iterator();
    while (iter.next()) |entry| {
        const id = entry.key_ptr.*;
        const file_data = AssetM.mAssetECS.GetComponent(FileMetaData, id);
        AssetM.mAssetGPA.allocator().free(file_data.mAbsPath);
    }
    AssetM.mAssetECS.Deinit();
    AssetM.mAssetMemoryPool.deinit();
    AssetM.mAssetPathToID.deinit();
    _ = AssetM.mAssetGPA.deinit();
    AssetM.mEngineAllocator.destroy(AssetM);
}

pub fn GetAssetHandleRef(abs_path: []const u8) !AssetHandle {
    if (AssetM.mAssetPathToID.get(abs_path)) |entity_id| {
        AssetM.mAssetECS.GetComponent(AssetMetaData, entity_id).mRefs += 1;
        return AssetHandle{
            .mID = entity_id,
        };
    } else {
        const asset_handle = try CreateAsset(abs_path);
        AssetM.mAssetECS.GetComponent(AssetMetaData, asset_handle.mID).mRefs += 1;
        try AssetM.mAssetPathToID.put(abs_path, asset_handle.mID);
        return asset_handle;
    }
}

pub fn ReleaseAssetHandleRef(asset_id: u32) void {
    const asset_meta_data = AssetM.mAssetECS.GetComponent(AssetMetaData, asset_id);
    asset_meta_data.mRefs -= 1;
    if (asset_meta_data.mRefs == 0) {
        SetAssetToDelete(asset_id);
    }
}

pub fn GetAsset(comptime asset_type: type, asset_id: u32) !*asset_type {
    if (asset_type == FileMetaData or asset_type == AssetMetaData or asset_type == IDComponent) {
        return AssetM.mAssetECS.GetComponent(asset_type, asset_id);
    }

    if (AssetM.mAssetECS.HasComponent(asset_type, asset_id)) {
        return AssetM.mAssetECS.GetComponent(asset_type, asset_id);
    } else {
        const file_data = AssetM.mAssetECS.GetComponent(FileMetaData, asset_id);
        const new_asset: asset_type = try asset_type.Init(file_data.mAbsPath);
        const new_component = try AssetM.mAssetECS.AddComponent(asset_type, asset_id, new_asset);
        return new_component;
    }
}

pub fn OnUpdate() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const group = try AssetM.mAssetECS.GetGroup(&[_]type{FileMetaData}, arena.allocator());
    var iter = group.iterator();
    while (iter.next()) |entry| {
        const id = entry.key_ptr.*;
        const file_data = AssetM.mAssetECS.GetComponent(FileMetaData, id);
        if (file_data.mSize == 0) {
            try CheckAssetToDelete(id);
            continue;
        }
        //then check if the asset path is still valid
        const file = std.fs.openFileAbsolute(file_data.mAbsPath, .{}) catch |err| {
            if (err == error.FileNotFound) {
                SetAssetToDelete(id);
                continue;
            } else {
                return err;
            }
        };
        defer file.close();

        //then check if the asset needs to be updated
        const fstats = try file.stat();
        if (file_data.mLastModified != fstats.mtime) {
            try UpdateAsset(id, file, fstats);
        }
    }
}

pub fn GetGroup(comptime ComponentTypes: []const type, allocator: std.mem.Allocator) !ArraySet(u32) {
    return try AssetM.mAssetECS.GetGroup(ComponentTypes, allocator);
}

fn CreateAsset(abs_path: []const u8) !AssetHandle {
    const new_handle = AssetHandle{
        .mID = try AssetM.mAssetECS.CreateEntity(),
    };
    _ = try AssetM.mAssetECS.AddComponent(AssetMetaData, new_handle.mID, .{
        .mRefs = 0,
    });

    _ = try AssetM.mAssetECS.AddComponent(FileMetaData, new_handle.mID, .{
        .mAbsPath = try AssetM.mAssetGPA.allocator().dupe(u8, abs_path),
        .mLastModified = 0,
        .mSize = 0,
        .mHash = 0,
    });

    _ = try AssetM.mAssetECS.AddComponent(IDComponent, new_handle.mID, .{
        .ID = try GenUUID(),
    });

    const file = std.fs.openFileAbsolute(abs_path, .{}) catch |err| {
        return err;
    };
    defer file.close();
    const fstats = try file.stat();

    try UpdateAsset(new_handle.mID, file, fstats);

    return new_handle;
}

fn DeleteAsset(asset_id: u32) !void {
    const file_data = AssetM.mAssetECS.GetComponent(FileMetaData, asset_id);
    _ = AssetM.mAssetPathToID.remove(file_data.mAbsPath);
    AssetM.mAssetGPA.allocator().free(file_data.mAbsPath);
    try AssetM.mAssetECS.DestroyEntity(asset_id);
}

fn SetAssetToDelete(asset_id: u32) void {
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

fn CheckAssetToDelete(asset_id: u32) !void {
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

const std = @import("std");
const GenUUID = @import("../Core/UUID.zig").GenUUID;
const Asset = @import("Asset.zig");
const AssetHandle = Asset.AssetHandle;
const AssetsList = @import("Assets.zig").AssetsList;
const ECSManager = @import("../ECS/ECSManager.zig");

const AssetManager = @This();

const ASSET_DELETE_TIMEOUT_NS: i128 = 1_000_000_000;
const MAX_FILE_SIZE: usize = 4_000_000_000;

var AssetM: *AssetManager = undefined;

mEngineAllocator: std.mem.Allocator,
mAssetGPA: std.heap.GeneralPurposeAllocator(.{}),
mAssetIDToAsset: std.AutoHashMap(u32, Asset),
mAssetMemoryManager: ECSManager,
mProjectDirectory: []const u8 = "",

pub fn Init(EngineAllocator: std.mem.Allocator) !void {
    AssetM = try EngineAllocator.create(AssetManager);
    AssetM.* = .{
        .mProjectDirectory = "",
        .mEngineAllocator = EngineAllocator,
        .mAssetGPA = std.heap.GeneralPurposeAllocator(.{}){},
        .mAssetIDToAsset = std.AutoHashMap(u32, Asset).init(AssetM.mAssetGPA.allocator()),
        .mAssetMemoryManager = try ECSManager.Init(AssetM.mAssetGPA.allocator(), &AssetsList),
    };
}

pub fn Deinit() void {
    AssetM.mAssetIDToAsset.deinit();
    AssetM.mAssetMemoryManager.Deinit();
    _ = AssetM.mAssetGPA.deinit();
    AssetM.mEngineAllocator.destroy(AssetM);
}

pub fn GetAssetHandleRef(abs_path: []const u8) *AssetHandle {
    var path_hasher = std.hash.Fnv1a_32.init();
    path_hasher.update(abs_path);
    const path_hash = path_hasher.final();

    if (AssetM.mAssetIDToAsset.getPtr(path_hash)) |asset| {
        asset.mRefs += 1;
        return &asset.mAssetHandle;
    } else {
        const asset = try CreateAsset(abs_path, path_hash);
        asset.mRefs += 1;
        return &asset.mAssetHandle;
    }
}

pub fn ReleaseAssetHandleRef(asset_id: u32) void {
    const asset = AssetM.mAssetIDToAsset.getPtr(asset_id).?;
    asset.mRefs -= 1;
    if (asset.mRefs == 0) {
        SetAssetToDelete(asset);
    }
}

pub fn GetAsset(comptime asset_type: type, asset_id: u32) *asset_type {
    return AssetM.mAssetMemoryManager.GetComponent(asset_type, AssetM.mAssetIDToAsset.get(asset_id).?.mInternalID);
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
        const file = std.fs.openFileAbsolute(asset.mPath, .{}) catch |err| {
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
            try UpdateAssetHandle(asset, file, fstats);
        }
    }
}

pub fn GetHandleMap() std.AutoHashMap(u32, Asset) {
    return AssetM.mAssetIDToAsset;
}

pub fn UpdateProjectDirectory(path: []const u8) !void {
    if (AssetM.mProjectDirectory.len > 0) {
        var iter = AssetM.mAssetIDToAsset.iterator();
        while (iter.next()) |entry| {
            AssetM.mAssetGPA.allocator().free(entry.value_ptr.mPath);
        }

        AssetM.mAssetIDToAsset.clearAndFree();

        AssetM.mAssetGPA.allocator().free(AssetM.mProjectDirectory);
    }

    AssetM.mProjectDirectory = try AssetM.mAssetGPA.allocator().dupe(u8, path);
}

fn CreateAsset(abs_path: []const u8, path_hash: u32) !*Asset {
    const file = std.fs.openFileAbsolute(abs_path, .{}) catch |err| {
        return err;
    };
    defer file.close();
    const fstats = try file.stat();

    var file_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer file_arena.deinit();
    const allocator = file_arena.allocator();
    var file_hasher = std.hash.Fnv1a_64.init();
    file_hasher.update(file.readToEndAlloc(allocator, MAX_FILE_SIZE));

    AssetM.mAssetIDToAsset.put(
        path_hash,
        .{
            .mAssetHandle = .{
                .mID = path_hash,
                .mLoadState = .NotLoaded,
            },
            .mRefs = 0,
            .mHash = file_hasher.final(),
            .mLastModified = fstats.mtime,
            .mPath = AssetM.mAssetGPA.allocator().dupe([]const u8, abs_path),
            .mSize = fstats.size,
        },
    );

    return AssetM.mAssetIDToAsset.getPtr(path_hash).?;
}

fn DeleteAsset(asset: *Asset) void {
    AssetM.mAssetGPA.allocator().free(asset.mPath);
    _ = AssetM.mAssetIDToAsset.remove(asset.mAssetHandle.mID);
}

fn SetAssetToDelete(asset: *Asset) void {
    asset.mSize = 0;
    asset.mLastModified = std.time.nanoTimestamp();
}

fn UpdateAssetHandle(asset: *Asset, file: std.fs.File, fstats: std.fs.File.Stat) !void {
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
    const file = std.fs.openFileAbsolute(asset.mPath, .{}) catch |err| {
        if (err == error.FileNotFound) {
            return false;
        } else {
            return err;
        }
    };
    defer file.close();

    const fstats = try file.stat();

    try UpdateAssetHandle(asset, file, fstats);

    return true;
}

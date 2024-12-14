const std = @import("std");
const GenUUID = @import("../Core/UUID.zig").GenUUID;
const AssetHandle = @import("AssetHandle.zig");
const AssetTypes = @import("AssetTypes.zig").AssetTypes;

//const Scene = @import("");
const Texture = @import("../Textures/Texture.zig").Texture;

const AssetManager = @This();

var AssetM: *AssetManager = undefined;

mEngineAllocator: std.mem.Allocator,
mAssetGPA: std.heap.GeneralPurposeAllocator(.{}),
mAssetPathToHandle: std.StringHashMap(AssetHandle),
mAssetHandleCache: std.DoublyLinkedList(AssetHandle),

mProjectDirectory: []const u8 = "",

//different asset types
//mAssetIDToTextureMap: std.AutoHashMap(u128, Texture),

pub fn Init(EngineAllocator: std.mem.Allocator) !void {
    AssetM = try EngineAllocator.create(AssetManager);
    AssetM.* = .{
        .mProjectDirectory = "",
        .mEngineAllocator = EngineAllocator,
        .mAssetGPA = std.heap.GeneralPurposeAllocator(.{}){},
        .mAssetPathToHandle = std.StringHashMap(AssetHandle).init(AssetM._AssetGPA.allocator()),
        //different asset types
        //.mAssetIDToTextureMap = std.AutoHashMap(u128, Texture).init(AssetM._AssetGPA.allocator()),
    };
}

pub fn Deinit() void {
    AssetM.mAssetPathToHandle.deinit();
    _ = AssetM.mAssetGPA.deinit();
    AssetM.mEngineAllocator.destroy(AssetM);
}

pub fn GetAssetHandle(abs_path: []const u8) AssetHandle {
    if (AssetM.mAssetPathToHandle.getPtr(abs_path)) |asset_handle| {
        asset_handle.mRefs += 1;
        return asset_handle;
    } else {
        const asset_handle = try CreateAssetHandle(abs_path);
        asset_handle.mRefs += 1;
        return asset_handle;
    }
}

pub fn ReleaseAssetHandle(asset_handle: *AssetHandle) void {
    asset_handle -= 1;
    if (asset_handle.mRefs == 0) {
        SetAssetHandleToDelete(asset_handle);
    }
}

fn CreateAssetHandle(abs_path: []const u8) !*AssetHandle {
    var path_hasher = std.hash.Fnv1a_128.init();
    path_hasher.update(abs_path);

    const file = std.fs.openFileAbsolute(abs_path, .{}) catch |err| {
        return err;
    };
    defer file.close();
    const fstats = try file.stat();

    var file_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = file_arena.allocator();
    var file_hasher = std.hash.Fnv1a_64.init();
    file_hasher.update(file.readToEndAlloc(allocator, 4000000000));

    AssetM.mAssetPathToHandle.put(
        abs_path,
        .{
            .mRefs = 0,
            .mHash = file_hasher.final(),
            .mLastModified = fstats.mtime,
            .mID = path_hasher.final(),
            .mPath = AssetM.mAssetGPA.allocator().dupe([]const u8, abs_path),
            .mSize = fstats.size,
        },
    );

    return AssetM.mAssetPathToHandle.getPtr(abs_path).?;
}

pub fn OnUpdate() !void {
    var iter = AssetM.mAssetPathToHandle.iterator();

    while (iter.next()) |entry| {
        const abs_path = entry.key_ptr.*;
        const asset_handle = entry.value_ptr;

        //first check to see if this asset will just get deleted
        if (asset_handle.mSize == 0) {
            if (std.time.nanoTimestamp() - asset_handle.mLastModified > 1000000000) {
                DeleteAssetHandle(abs_path, asset_handle);
            }
            continue;
        }

        //then check if the asset path is still valid
        const file = std.fs.openFileAbsolute(abs_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                SetAssetHandleToDelete(asset_handle);
                continue;
            } else {
                return err;
            }
        };
        defer file.close();

        //then check if the asset needs to be updated
        const fstats = try file.stat();
        if (asset_handle.mLastModified != fstats.mtime) {
            UpdateAssetHandle(asset_handle, file, fstats);
        }
    }
}

fn DeleteAssetHandle(abs_path: []const u8, asset_handle: AssetHandle) void {
    AssetM.mAssetGPA.allocator().free(asset_handle.mPath);
    AssetM.mAssetPathToHandle.remove(abs_path);
}

fn SetAssetHandleToDelete(asset_handle: *AssetHandle) void {
    asset_handle.mSize = 0;
    asset_handle.mLastModified = std.time.nanoTimestamp();
}

fn UpdateAssetHandle(asset_handle: *AssetHandle, file: std.fs.File, fstats: std.fs.File.Stat) void {
    var file_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = file_arena.allocator();
    var file_hasher = std.hash.Fnv1a_64.init();
    file_hasher.update(file.readToEndAlloc(allocator, 4000000000));

    asset_handle.mHash = file_hasher.final();
    asset_handle.mLastModified = fstats.mtime;
    asset_handle.mSize = fstats.size;
}

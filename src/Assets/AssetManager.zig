const std = @import("std");
const GenUUID = @import("../Core/UUID.zig").GenUUID;
const AssetHandle = @import("AssetHandle.zig");
const AssetTypes = @import("AssetTypes.zig").AssetTypes;

//const Scene = @import("");
const Texture = @import("../Textures/Texture.zig").Texture;

const AssetManager = @This();

var AssetM: *AssetManager = undefined;

_EngineAllocator: std.mem.Allocator,
_AssetGPA: std.heap.GeneralPurposeAllocator(.{}),
_AssetPathToIDMap: std.StringHashMap(u128),
_AssetIDToHandleMap: std.AutoHashMap(u128, AssetHandle),
_AssetPathToIDDelete: std.StringHashMap(u128),
_AssetIDToHandleDelete: std.AutoHashMap(u128, AssetHandle),
_ProjectDirectory: []const u8 = "",

//different asset types
_AssetIDToTextureMap: std.AutoHashMap(u128, Texture),

pub fn Init(EngineAllocator: std.mem.Allocator) !void {
    AssetM = try EngineAllocator.create(AssetManager);
    AssetM.* = .{
        ._ProjectDirectory = "",
        ._EngineAllocator = EngineAllocator,
        ._AssetGPA = std.heap.GeneralPurposeAllocator(.{}){},
        ._AssetPathToIDMap = std.StringHashMap(u128).init(AssetM._AssetGPA.allocator()),
        ._AssetIDToHandleMap = std.AutoHashMap(u128, AssetHandle).init(AssetM._AssetGPA.allocator()),
        ._AssetPathToIDDelete = std.StringHashMap(u128).init(AssetM._AssetGPA.allocator()),
        ._AssetIDToHandleDelete = std.AutoHashMap(u128, AssetHandle).init(AssetM._AssetGPA.allocator()),

        //different asset types
        ._AssetIDToTextureMap = std.AutoHashMap(u128, Texture).init(AssetM._AssetGPA.allocator()),
    };
}

pub fn Deinit() void {
    var iter = AssetM._AssetPathToIDMap.iterator();

    while (iter.next()) |entry| {
        AssetM._AssetGPA.allocator().free(entry.key_ptr.*);
    }
    AssetM._AssetPathToIDMap.deinit();
    AssetM._AssetIDToHandleMap.deinit();

    iter = AssetM._AssetPathToIDDelete.iterator();
    while (iter.next()) |entry| {
        AssetM._AssetGPA.allocator().free(entry.key_ptr.*);
    }
    AssetM._AssetPathToIDDelete.deinit();
    AssetM._AssetIDToHandleDelete.deinit();

    //different asset types
    AssetM._AssetIDToTextureMap.deinit();
    if (AssetM._ProjectDirectory.len > 0) {
        AssetM._AssetGPA.allocator().free(AssetM._ProjectDirectory);
    }
    _ = AssetM._AssetGPA.deinit();
    AssetM._EngineAllocator.destroy(AssetM);
}

pub fn CreateOrGetAssetHandle(abs_path: []const u8) AssetHandle {
    if (AssetM._AssetPathToIDMap.get(abs_path)) |asset_id| {
        return GetAssetHandle(asset_id);
    } else {
        CreateAssetHandle(abs_path);
    }
}

pub fn CreateAssetHandle(abs_path: []const u8, assetType: AssetTypes, size: u64, modifyTime: i128, hash: u64) !void {
    //id
    const id = try GenUUID();

    const handle = AssetHandle{
        ._AssetLastModified = modifyTime,
        ._AssetSize = size,
        ._AssetHash = hash,
        ._AssetType = assetType,
        ._AssetPath = try AssetM._AssetGPA.allocator().dupe(u8, abs_path),
    };
    try AssetM._AssetPathToIDMap.put(handle._AssetPath, id);
    try AssetM._AssetIDToHandleMap.put(id, handle);
}

pub fn GetAssetHandle(id: u128) AssetHandle {
    return AssetM._AssetIDToHandleMap.get(id).?;
}

pub fn UpdateProjectDirectory(path: []const u8) !void {
    if (AssetM._ProjectDirectory.len > 0) {
        var iter = AssetM._AssetPathToIDMap.iterator();
        while (iter.next()) |entry| {
            AssetM._AssetGPA.allocator().free(entry.key_ptr.*);
        }
        AssetM._AssetPathToIDMap.clearAndFree();
        AssetM._AssetIDToHandleMap.clearAndFree();
        AssetM._AssetIDToTextureMap.clearAndFree();

        iter = AssetM._AssetPathToIDDelete.iterator();
        while (iter.next()) |entry| {
            AssetM._AssetGPA.allocator().free(entry.key_ptr.*);
        }
        AssetM._AssetPathToIDDelete.clearAndFree();
        AssetM._AssetIDToHandleDelete.clearAndFree();

        AssetM._AssetGPA.allocator().free(AssetM._ProjectDirectory);
    }

    AssetM._ProjectDirectory = try AssetM._AssetGPA.allocator().dupe(u8, path);
}

pub fn OnUpdate() !void {
    //no project == no assets
    if (AssetM._ProjectDirectory.len == 0) return;

    //for reading files later
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    //Walk dir
    var dir = try std.fs.openDirAbsolute(AssetM._ProjectDirectory, .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (true) {
        const entry = walker.next() catch |err| {
            switch (err) {
                error.Unexpected => {
                    continue;
                },
                else => return err,
            }
        } orelse break;

        if (entry.kind != .file) continue;

        const rel_path = entry.path;
        const abs_path = try std.fs.path.join(allocator, &[_][]const u8{ AssetM._ProjectDirectory, rel_path });

        //if Asset type is an accepted asset type
        const file_extension = std.fs.path.extension(rel_path);
        const asset_type = .NotAsset;
        if (std.mem.eql(u8, file_extension, ".png") == true) {
            asset_type = .PNG;
        }
        if (asset_type != .NotAsset) {
            const asset_handle = CreateOrGetAssetHandle(abs_path);
            const file = std.fs.openFileAbsolute(abs_path, .{}) catch |err| {
                if (err == error.FileNotFound) {
                    try HandleDeletedAssets(asset_handle);
                    continue;
                } else {
                    return err;
                }
            };
            defer file.close();

            const fstats = try file.stat();

            if (fstats.mtime != asset_handle._AssetLastModified) {
                try HandleModifiedAssets(asset_handle, fstats.mtime);
            }
        }
        CleanUpDeletedAssets();
    }
}

pub fn GetHandleMap() *const std.AutoHashMap(u128, AssetHandle) {
    return &AssetM._AssetIDToHandleMap;
}

pub fn GetNumHandles() u32 {
    return AssetM._AssetIDToHandleMap.count();
}

fn HandleDeletedAssets(asset_handle: AssetHandle) !void {
    var new_handle = asset_handle;
    new_handle._AssetLastModified = std.time.nanoTimestamp();

    _ = AssetM._AssetPathToIDMap.remove(asset_handle._AssetAbsPath);
    _ = AssetM._AssetIDToHandleMap.remove(asset_handle._AssetID);
    if (asset_handle._AssetType == .Texture) {
        _ = AssetM._AssetIDToTextureMap.remove(asset_handle);
    }

    try AssetM._AssetPathToIDDelete.put(asset_handle.mAbsPath, asset_handle.mID);
    try AssetM._AssetIDToHandleDelete.put(new_handle.mID, new_handle);
}

fn HandleModifiedAssets(id: u128, handle: AssetHandle, abs_path: []const u8, new_mtime: i128) !void {
    var new_handle = handle;
    new_handle._AssetLastModified = new_mtime;

    if (std.mem.eql(u8, std.fs.path.extension(new_handle._AssetPath), ".png") == true) {
        if (AssetM._AssetIDToTextureMap.getEntry(id)) |entry| {
            try entry.value_ptr.UpdateDataPath(abs_path);
        }
    }

    try AssetM._AssetIDToHandleMap.put(id, new_handle);
}

fn RestoreDeletedAsset(old_rel_path: []const u8, id: u128, handle: AssetHandle, new_rel_path: []const u8, new_mtime: i128) !void {
    var new_handle = handle;
    new_handle._AssetPath = try AssetM._AssetGPA.allocator().dupe(u8, new_rel_path);
    new_handle._AssetLastModified = new_mtime;

    try AssetM._AssetPathToIDMap.put(new_handle._AssetPath, id);
    try AssetM._AssetIDToHandleMap.put(id, new_handle);
    _ = AssetM._AssetPathToIDDelete.remove(old_rel_path);
    _ = AssetM._AssetIDToHandleDelete.remove(id);

    AssetM._AssetGPA.allocator().free(handle._AssetPath);
}

fn CleanUpDeletedAssets() !void {
    const current_time = std.time.nanoTimestamp();
    var iter = AssetM._AssetPathToIDDelete.iterator();
    while (iter.next()) |entry| {
        const rel_path = entry.key_ptr.*;
        const id = entry.value_ptr.*;
        if (AssetM._AssetIDToHandleDelete.get(id)) |handle| {
            if (current_time - handle._AssetLastModified > 1000000000) {
                _ = AssetM._AssetPathToIDDelete.remove(rel_path);
                _ = AssetM._AssetIDToHandleDelete.remove(id);
                AssetM._AssetGPA.allocator().free(rel_path);
            }
        }
    }
}

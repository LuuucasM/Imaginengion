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
mAssetPathToHandleDelete: std.StringHashMap(AssetHandle),
mProjectDirectory: []const u8 = "",

//different asset types
mAssetIDToTextureMap: std.AutoHashMap(u128, Texture),

pub fn Init(EngineAllocator: std.mem.Allocator) !void {
    AssetM = try EngineAllocator.create(AssetManager);
    AssetM.* = .{
        .mProjectDirectory = "",
        .mEngineAllocator = EngineAllocator,
        .mAssetGPA = std.heap.GeneralPurposeAllocator(.{}){},
        .mAssetPathToHandle = std.StringHashMap(AssetHandle).init(AssetM._AssetGPA.allocator()),
        .mAssetPathToHandleDelete = std.StringHashMap(AssetHandle).init(AssetM._AssetGPA.allocator()),

        //different asset types
        .mAssetIDToTextureMap = std.AutoHashMap(u128, Texture).init(AssetM._AssetGPA.allocator()),
    };
}

pub fn Deinit() void {
    AssetM.mAssetPathToHandle.deinit();
    AssetM.mAssetPathToHandleDelete.deinit();

    //different asset types
    AssetM.mAssetIDToTextureMap.deinit();
    if (AssetM.mProjectDirectory.len > 0) {
        AssetM.mAssetGPA.allocator().free(AssetM.mProjectDirectory);
    }
    _ = AssetM.mAssetGPA.deinit();
    AssetM.mEngineAllocator.destroy(AssetM);
}

pub fn GetAsset(abs_path: []const u8) AssetHandle {
    return CreateOrGetAssetHandle(abs_path);
}

fn CreateOrGetAssetHandle(abs_path: []const u8) AssetHandle {
    if (AssetM.mAssetPathToHandle.get(abs_path)) |asset_handle| {
        return asset_handle;
    } else {
        CreateAssetHandle(abs_path);
    }
}

fn CreateAssetHandle(abs_path: []const u8) !void {
    const handle = AssetHandle{
        .mID = try GenUUID(),
        .mLastModified = modifyTime,
        .mSize = size,
        .mHash = hash,
        .mType = assetType,
        .mAbsPath = try AssetM._AssetGPA.allocator().dupe(u8, abs_path),
    };
    try AssetM._AssetPathToHandle.put(abs_path, handle);
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

    //check current handles to see if they are still up to date
    //and that they still exist
    CheckHandles(allocator);

    //walk from the project directory to find any new assets or
    //possibly recover modified assets
    WalkDir(allocator);

    //for handles that are for sure deleted now
    CleanUpHandles();
}

fn CheckHandles(allocator: std.mem.Allocator) void {
    var iter = AssetM.mAssetPathToHandle.iterator();

    while (iter.next()) |entry| {
        const abs_path = entry.key_ptr.*;
        const handle = entry.value_ptr.*;

        const file = std.fs.openFileAbsolute(abs_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                try HandleDeletedAssets(handle);
                continue;
            } else {
                return err;
            }
        };
        defer file.close();

        //check if the file has been modified
        const fstats = try file.stat();
        if (fstats.mtime != handle.mLastModified) {
            try HandleModifiedAsset(handle, file, fstats, allocator);
        }
    }
}

fn WalkDir(allocator: std.mem.Allocator) void {
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

        const file_extension = std.fs.path.extension(rel_path);
        const asset_type = .NotAsset;
        if (std.mem.eql(u8, file_extension, ".png") == true) {
            asset_type = .PNG;
        }
        if (asset_type != .NotAsset) {
            //check if the file still exists
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

            //check if the file has been modified
            const fstats = try file.stat();

            if (fstats.mtime != asset_handle._AssetLastModified) {
                try HandleModifiedAsset(asset_handle, file, fstats.mtime, allocator);
            }
        }
    }
}

fn CleanUpHandles() void {}

fn HandleDeletedAssets(asset_handle: AssetHandle) !void {
    var new_handle = asset_handle;
    //set asset last modified to the current time
    //so we can keep the handle around for 1-2 seconds before deleting
    new_handle._AssetLastModified = std.time.nanoTimestamp();

    _ = AssetM._AssetPathToIDMap.remove(asset_handle._AssetAbsPath);
    _ = AssetM._AssetIDToHandleMap.remove(asset_handle._AssetID);
    if (asset_handle._AssetType == .Texture) {
        _ = AssetM._AssetIDToTextureMap.remove(asset_handle);
    }

    try AssetM._AssetPathToIDDelete.put(asset_handle.mAbsPath, asset_handle.mID);
    try AssetM._AssetIDToHandleDelete.put(new_handle.mID, new_handle);
}

fn HandleModifiedAsset(asset_handle: AssetHandle, file: std.fs.File, stats: std.fs.File.Stat, allocator: std.mem.Allocator) void {
    asset_handle.mSize = stats.size;

    asset_handle.mLastModified = stats.mtime;

    //update hash
    const content = try file.readToEndAlloc(allocator, @intCast(fstats.size));
    defer allocator.free(content);

    var hasher = std.hash.Wyhash.init(0);
    hasher.update(content);
    const hash = hasher.final();

    asset_handle.mHash = hash;
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

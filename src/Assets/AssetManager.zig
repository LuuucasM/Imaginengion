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
    if (AssetM._ProjectDirectory.len > 0){
        AssetM._AssetGPA.allocator().free(AssetM._ProjectDirectory);
    }
    _ = AssetM._AssetGPA.deinit();
    AssetM._EngineAllocator.destroy(AssetM);
}

pub fn GetAssetID(path: []const u8) ?u128 {
    return AssetM._AssetPathToIDMap.get(path);
}

pub fn GetAssetHandle(id: u128) ?AssetHandle {
    return AssetM._AssetIDToHandleMap.get(id);
}

pub fn GetAsset(comptime T: type, id: u128) ?T {
    if (T == Texture) {
        return AssetM._AssetIDToTextureMap.get(id);
    } else {
        @compileError("Type not supported yet");
    }
}

pub fn CreateAssetHandle(rel_path: []const u8, assetType: AssetTypes, size: u64, modifyTime: i128, hash: u64) !void {
    //id
    const id = try GenUUID();

    const handle = AssetHandle{
        ._AssetLastModified = modifyTime,
        ._AssetSize = size,
        ._AssetHash = hash,
        ._AssetType = assetType,
        ._AssetPath = try AssetM._AssetGPA.allocator().dupe(u8, rel_path),
    };
    try AssetM._AssetPathToIDMap.put(handle._AssetPath, id);
    try AssetM._AssetIDToHandleMap.put(id, handle);
}

pub fn UpdateProjectDirectory(path: []const u8) !void {
    if (AssetM._ProjectDirectory.len > 0){
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
    if (AssetM._ProjectDirectory.len == 0) return;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var iter = AssetM._AssetPathToIDMap.iterator();
    while (iter.next()) |entry| {
        const rel_path = entry.key_ptr.*;
        const id = entry.value_ptr.*;
        const abs_path = try std.fs.path.join(arena.allocator(), &[_][]const u8{ AssetM._ProjectDirectory, rel_path });
        const handle = AssetM._AssetIDToHandleMap.get(id).?;
        const file = std.fs.openFileAbsolute(abs_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                try HandleDeletedAssets(rel_path, id, handle);
                continue;
            } else {
                return err;
            }
        };
        defer file.close();

        const fstats = try file.stat();

        if (fstats.mtime != handle._AssetLastModified) {
            try HandleModifiedAssets(id, handle, abs_path, fstats.mtime);
        }
    }

    try WalkDirectory(arena.allocator());

    try CleanUpDeletedAssets();
}

pub fn GetHandleMap() *const std.AutoHashMap(u128, AssetHandle) {
    return &AssetM._AssetIDToHandleMap;
}

pub fn GetNumHandles() u32 {
    return AssetM._AssetIDToHandleMap.count();
}

fn HandleDeletedAssets(rel_path: []const u8, id: u128, handle: AssetHandle) !void {
    var new_handle = handle;
    new_handle._AssetLastModified = std.time.nanoTimestamp();

    _ = AssetM._AssetPathToIDMap.remove(rel_path);
    _ = AssetM._AssetIDToHandleMap.remove(id);
    if (handle._AssetType == .Texture) {
        _ = AssetM._AssetIDToTextureMap.remove(id);
    }

    try AssetM._AssetPathToIDDelete.put(rel_path, id);
    try AssetM._AssetIDToHandleDelete.put(id, new_handle);
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

fn WalkDirectory(allocator: std.mem.Allocator) !void {
    var dir = try std.fs.openDirAbsolute(AssetM._ProjectDirectory, .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (true) {
        const entry = walker.next() catch |err| {
            switch(err){
                error.Unexpected => {
                    continue;
                },
                else => return err,
            }
        } orelse break;

        if (entry.kind != .file) continue;

        const abs_path = try std.fs.path.join(allocator, &[_][]const u8{ AssetM._ProjectDirectory, entry.path });
        const rel_path = entry.path;

        if (AssetM._AssetPathToIDMap.contains(rel_path)) continue;

        const asset_type = if (std.mem.eql(u8, std.fs.path.extension(rel_path), ".png") == true) AssetTypes.Texture else AssetTypes.NotAsset;
        if (asset_type != .NotAsset) {
            try HandleNewAsset(allocator, abs_path, rel_path, asset_type);
        }
    }
}

fn HandleNewAsset(allocator: std.mem.Allocator, abs_path: []const u8, rel_path: []const u8, assetType: AssetTypes) !void {
    var file = try std.fs.openFileAbsolute(abs_path, .{});
    defer file.close();
    const fstats = try file.stat();

    const content = try file.readToEndAlloc(allocator, @intCast(fstats.size));
    defer allocator.free(content);

    var hasher = std.hash.Wyhash.init(0);
    hasher.update(content);
    const hash = hasher.final();

    var found_match = false;
    var iter = AssetM._AssetPathToIDDelete.iterator();
    while (iter.next()) |entry| {
        const delete_path = entry.key_ptr.*;
        const delete_id = entry.value_ptr.*;
        if (AssetM._AssetIDToHandleDelete.get(delete_id)) |delete_handle| {
            if (delete_handle._AssetSize == fstats.size and delete_handle._AssetHash == hash and delete_handle._AssetType == assetType) {
                try RestoreDeletedAsset(delete_path, delete_id, delete_handle, rel_path, fstats.mtime);
                found_match = true;
                break;
            }
        }
    }
    if (found_match == false) {
        try CreateAssetHandle(rel_path, assetType, fstats.size, fstats.mtime, hash);
    }
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

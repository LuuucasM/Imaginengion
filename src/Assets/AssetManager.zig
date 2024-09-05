const std = @import("std");
const GenUUID = @import("../Core/UUID.zig").GenUUID;
const AssetHandle = @import("AssetHandle.zig");
const AssetTypes = @import("AssetTypes.zig").AssetTypes;

//const Scene = @import("");
const Texture = @import("../Textures/Texture.zig");

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
    const asset_gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const asset_allocator = asset_gpa.allocator();
    AssetM = try EngineAllocator.create(AssetManager);
    AssetM.* = .{
        ._EngineAllocator = EngineAllocator,
        ._AssetGPA = asset_gpa,
        ._AssetPathToIDMap = std.StringHashMap(u128).init(asset_allocator),
        ._AssetIDToHandleMap = std.AutoHashMap(u128, AssetHandle).init(asset_allocator),
        ._AssetPathToIDDelete = std.StringHashMap(u128).init(asset_allocator),
        ._AssetIDToHandleDelete = std.AutoHashMap(u128, AssetHandle).init(asset_allocator),
        //different asset types
        ._AssetIDToTextureMap = std.AutoHashMap(u128, Texture).init(asset_allocator),
    };
}

pub fn Deinit() void {
    AssetM._AssetGPA.deinit();
    AssetM._AssetPathToIDMap.deinit();
    AssetM._AssetIDToHandleMap.deinit();
    AssetM._AssetPathToIDDelete.deinit();
    AssetM._AssetIDToHandleDelete.deinit();

    //different asset types
    AssetM._AssetIDToTextureMap.deinit();

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

pub fn CreateAssetHandle(comptime T: type, abs_path: []const u8) !T {
    //type
    const assetType = if (T == Texture) AssetTypes.Texture else @compileError("Type not supported yet");

    const rel_path = abs_path[AssetM._ProjectDirectory.len..];

    //id
    const id = GenUUID();

    const f = try std.fs.openFileAbsolute(abs_path, .{});
    defer f.close();
    const fstat = try f.stat();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const content = try f.readToEndAlloc(arena.allocator(), fstat.size);
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(content);
    const hash = hasher.final();

    const handle = AssetHandle{
        ._AssetHash = hash,
        ._AssetLastModified = fstat.mtime,
        ._AssetPath = rel_path,
        ._AssetSize = fstat.size,
        ._AssetType = assetType,
    };

    try AssetM._AssetPathToIDMap.put(rel_path, id);
    try AssetM._AssetIDToHandleMap.put(id, handle);

    return handle;
}

pub fn UpdateProjectDirectory(path: []const u8) void {
    AssetM._ProjectDirectory = path;
}

pub fn OnUpdate() !void {
    if (AssetM._ProjectDirectory.len == 0) return;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var iter = AssetM._AssetPathToIDMap.iterator();
    while (iter.next()) |entry| {
        const rel_path = entry.key_ptr.*;
        const abs_path = try std.fs.path.join(arena.allocator(), &[_][]const u8{ AssetM._ProjectDirectory, rel_path });
        const id = entry.value_ptr.*;
        const handle = AssetM._AssetIDToHandleMap.get(id) orelse continue;
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

    if (handle._AssetType == .Texture) {
        if (AssetM._AssetIDToTextureMap.get(id)) |texture| {
            try texture.SetDataFromPath(abs_path);
        }
    }

    try AssetM._AssetIDToHandleMap.put(id, new_handle);
}

fn WalkDirectory(allocator: std.mem.Allocator) !void {
    var dir = try std.fs.openDirAbsolute(AssetM._ProjectDirectory, .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;

        const abs_path = entry.path;
        const rel_path = abs_path[AssetM._ProjectDirectory.len..];

        if (AssetM._AssetPathToIDMap.contains(rel_path)) continue;

        try HandleNewAsset(allocator, abs_path, rel_path);
    }
}

fn HandleNewAsset(allocator: std.mem.Allocator, abs_path: []const u8, rel_path: []const u8) !void {
    var file = try std.fs.openFileAbsolute(abs_path, .{});
    defer file.close();
    const fstats = try file.stat();

    const content = try file.readToEndAlloc(allocator, fstats.size);
    defer allocator.free(content);

    var hasher = std.hash.Wyhash.init(0);
    hasher.update(content);
    const hash = hasher.final();

    var found_match = false;
    var iter = AssetM._AssetPathToIDDelete.iterator();
    while (iter.next()) |entry| {
        const delete_id = entry.value_ptr.*;
        if (AssetM._AssetIDToHandleDelete.get(delete_id)) |delete_handle| {
            if (delete_handle._AssetSize == fstats.size and delete_handle._AssetHash == hash and delete_handle._AssetType == .Texture) {
                try RestoreDeletedAsset(entry.key_ptr.*, delete_id, delete_handle, rel_path, fstats.mtime);
                found_match = true;
                break;
            }
        }
    }
    if (found_match == false) {
        try CreateAssetHandle(Texture, rel_path);
    }
}

fn RestoreDeletedAsset(old_rel_path: []const u8, id: u128, handle: AssetHandle, new_rel_path: []const u8, new_mtime: i128) !void {
    var new_handle = handle;
    new_handle._AssetPath = new_rel_path;
    new_handle._AssetLastModified = new_mtime;

    _ = AssetM._AssetPathToIDDelete.remove(old_rel_path);
    _ = AssetM._AssetIDToHandleDelete.remove(id);
    try AssetM._AssetPathToIDMap.put(new_rel_path, id);
    try AssetM._AssetIDToHandleMap.put(id, new_handle);
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
            }
        }
    }
}

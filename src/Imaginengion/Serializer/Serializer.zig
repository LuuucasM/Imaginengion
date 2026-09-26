const std = @import("std");

const EngineContext = @import("../Core/EngineContext.zig");

const AssetHandle = @import("../ECSObjects/AssetHandle.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const GameContext = @import("../ECSObjects/GameContext.zig");
const Player = @import("../ECSObjects/Player.zig");
const Scene = @import("../ECSObjects/Scene.zig");

const TextSerializer = @import("TextSerializer.zig");

const PlatformUtils = @import("../PlatformUtils/PlatformUtils.zig");

const Serializer = @This();

pub const SerializeType = enum {
    Text,
    Binary,
};

/// The ECS object that owns the component currently being deserialized
pub const Requester = union(enum(u16)) {
    Entity: Entity,
    Scene: Scene,
    Player: Player,
    GameContext: GameContext,

    pub const default: Requester = .{ .Entity = .uninit };

    pub fn Init(object: anytype) Requester {
        const obj_t = @TypeOf(object);
        if (obj_t == Entity) {
            return .{ .Entity = object };
        } else if (obj_t == Scene) {
            return .{ .Scene = object };
        } else if (obj_t == Player) {
            return .{ .Player = object };
        } else if (obj_t == GameContext) {
            return .{ .GameContext = object };
        } else {
            @compileError(std.fmt.comptimePrint("{s} is not a valid requester type", .{@typeName(obj_t)}));
        }
    }

    pub fn IsActive(self: Requester) bool {
        return switch (self) {
            inline else => |object| object.IsActive(),
        };
    }
};

/// A reference to another ECS object (stored as a UUID in the file) that cannot be turned into a world ID
/// until the object it points at has been loaded. Resolve looks the UUID up and writes the result into the
/// requester's component, returning false if the UUID is not loaded yet so the request is retried later.
/// It re-fetches the component rather than holding a pointer to it because component storage can move.
pub const ResolveReq = struct {
    Requester: Requester,
    UUID: u64,
    Resolve: *const fn (requester: Requester, uuid: u64) bool,
};

pub const DeserializeContext = struct {
    requester: Requester,

    pub const empty: DeserializeContext = .{
        .requester = .default,
    };
};

pub const empty: Serializer = .{
    .mFileObjects = .empty,
    .mPendingResolves = .empty,
    .mCurrDeserialize = .empty,
};

/// Object UUID -> the file it was last saved to / loaded from
mFileObjects: std.AutoHashMapUnmanaged(u64, AssetHandle),
mPendingResolves: std.ArrayList(ResolveReq),
mCurrDeserialize: DeserializeContext,

/// Releases the file handles it holds, so it has to go before the asset manager does
pub fn Deinit(self: *Serializer, engine_allocator: std.mem.Allocator) void {
    var file_iter = self.mFileObjects.valueIterator();
    while (file_iter.next()) |asset_handle| {
        asset_handle.ReleaseAsset();
    }
    self.mFileObjects.deinit(engine_allocator);
    self.mPendingResolves.deinit(engine_allocator);
}

pub fn SaveECSObject(self: *Serializer, engine_context: *EngineContext, object: anytype) !void {
    if (self.mFileObjects.get(object.GetUUID())) |asset_handle| {
        const file_data = asset_handle.GetFileMetaData();
        const abs_path = try engine_context.mAssetManager.GetAbsPath(engine_context.FrameAllocator(), file_data.mRelPath.items, file_data.mPathType);
        try SerializeECSObject(engine_context, object, abs_path, .Text);
    } else {
        try self.SaveECSObjAs(engine_context, object);
    }
}

pub fn SaveECSObjAs(self: *Serializer, engine_context: *EngineContext, object: anytype) !void {
    const abs_path = try PlatformUtils.SaveFile(engine_context.FrameAllocator(), FileExtension(@TypeOf(object)));
    if (abs_path.len == 0) return;

    try SerializeECSObject(engine_context, object, abs_path, .Text);
    try self.TrackFile(engine_context, object.GetUUID(), abs_path);
}

/// Fills an already created object from the file at abs_path. The object should be blank
/// (created without the default UUID/Name/Transform components) since those come from the file.
pub fn DeserializeECSObj(self: *Serializer, engine_context: *EngineContext, object: anytype, abs_path: []const u8, comptime deserialize_type: SerializeType) !void {
    switch (deserialize_type) {
        .Text => try TextSerializer.DeserializeECSObj(engine_context, object, abs_path),
        .Binary => @compileError("Binary deserialization is not implemented yet"),
    }

    self.ResolveUUIDs();

    try self.TrackFile(engine_context, object.GetUUID(), abs_path);
}

pub fn AddResolveReq(self: *Serializer, engine_allocator: std.mem.Allocator, resolve_req: ResolveReq) !void {
    try self.mPendingResolves.append(engine_allocator, resolve_req);
}

/// Resolves every pending UUID reference whose target is now loaded. Requests whose target is not loaded
/// yet are kept for the next call, and requests whose requester has since been destroyed are dropped.
pub fn ResolveUUIDs(self: *Serializer) void {
    var i: usize = 0;
    while (i < self.mPendingResolves.items.len) {
        const request = self.mPendingResolves.items[i];
        if (!request.Requester.IsActive() or request.Resolve(request.Requester, request.UUID)) {
            _ = self.mPendingResolves.swapRemove(i);
        } else {
            i += 1;
        }
    }
}

fn SerializeECSObject(engine_context: *EngineContext, object: anytype, abs_path: []const u8, comptime serialize_type: SerializeType) !void {
    switch (serialize_type) {
        .Text => try TextSerializer.SerializeECSObject(engine_context, object, abs_path),
        .Binary => @compileError("Binary serialization is not implemented yet"),
    }
}

/// Remembers which file an object lives in so SaveECSObject can overwrite it without asking again
fn TrackFile(self: *Serializer, engine_context: *EngineContext, uuid: u64, abs_path: []const u8) !void {
    const rel_path = engine_context.mAssetManager.GetRelPath(abs_path, .Prj);
    const asset_handle = try engine_context.mAssetManager.GetAssetHandle(engine_context, .{ .File = .{ .rel_path = rel_path, .path_type = .Prj } });

    const entry = try self.mFileObjects.getOrPut(engine_context.EngineAllocator(), uuid);
    if (entry.found_existing) entry.value_ptr.ReleaseAsset();
    entry.value_ptr.* = asset_handle;
}

/// The kind of object a file with this extension holds, the other way round from FileExtension
pub const ObjectKind = enum { Entity, Scene, Player, GameContext };
pub fn ObjectKindOf(extension: []const u8) ?ObjectKind {
    inline for (.{ .{ Entity, ObjectKind.Entity }, .{ Scene, ObjectKind.Scene }, .{ Player, ObjectKind.Player }, .{ GameContext, ObjectKind.GameContext } }) |pair| {
        if (std.mem.eql(u8, extension, std.mem.span(FileExtension(pair[0])))) return pair[1];
    }
    return null;
}

pub fn FileExtension(comptime obj_t: type) [*c]const u8 {
    if (obj_t == Scene) {
        return ".imsc";
    } else if (obj_t == Entity) {
        return ".imen";
    } else if (obj_t == Player) {
        return ".impl";
    } else if (obj_t == GameContext) {
        return ".imgc";
    } else {
        @compileError(std.fmt.comptimePrint("Saving {s} to a file is not supported yet", .{@typeName(obj_t)}));
    }
}

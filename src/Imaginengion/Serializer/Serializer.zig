const std = @import("std");
const SceneLayer = @import("../Scene/SceneLayer.zig");
const Entity = @import("../GameObjects/Entity.zig");
const Player = @import("../Players/Player.zig");
const GameMode = @import("../GameModes/GameMode.zig");

const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;

const Renderer = @import("../Renderer/Renderer.zig");

const EngineContext = @import("../Core/EngineContext.zig");
const WorldType = EngineContext.WorldType;

const WriteStream = std.json.Stringify;
const StringifyOptions = std.json.Stringify.Options{ .whitespace = .indent_2 };
const PARSE_OPTIONS = std.json.ParseOptions{ .allocate = .alloc_if_needed, .max_value_len = std.json.default_max_value_len };

const WorldManager = @import("../Core/WorldManager.zig");

const TextSerializer = @import("TextSerializer.zig");
const BinarySerializer = @import("BinarySerializer.zig");

const AssetHandle = @import("../ECSObjects/AssetHandle.zig");

const PlatformUtils = @import("../PlatformUtils/PlatformUtils.zig");

const Serializer = @This();

pub const SerializeType = enum {
    Text,
    Binary,
};

pub const Requester = union(enum(u16)) {
    Entity: Entity,
    Scene: SceneLayer,
    Player: Player,
    GameMode: GameMode,

    pub const default: Requester = .{ .Entity = .{} };
};

pub const ResolveReq = struct {
    Requester: Requester,
    UUID: u64,
    SetLoc: *anyopaque,
};

pub const DeserializeContext = struct {
    requester: Requester,
    component_ptr: *anyopaque,

    pub const empty: DeserializeContext = .{
        .requester = .default,
        .component_ptr = undefined,
    };
};

pub const empty: Serializer = .{
    .mCurrDeserialize = .empty,
    .mFileObjects = .empty,
};

mFileObjects: std.AutoHashMapUnmanaged(u64, AssetHandle),
mCurrDeserialize: DeserializeContext,

pub fn Deinit(self: Serializer, engine_allocator: std.mem.Allocator) void {
    self.mFileObjects.deinit(engine_allocator);
}

pub fn SaveECSObject(self: Serializer, engine_context: *EngineContext, object: anytype) !void {
    const uuid = object.GetUUID();
    if (self.mFileObjects.get(uuid)) |asset_handle| {
        const file_data = asset_handle.GetFileMetaData();
        const abs_path = try engine_context.mAssetManager.GetAbsPath(engine_context.FrameAllocator(), file_data.mRelPath, file_data.mPathType);
        SerializeECSObject(self, engine_context, object, abs_path, .Text);
    } else {
        self.SaveECSObjAs(engine_context, object);
    }
}

pub fn SaveECSObjAs(self: Serializer, engine_context: *EngineContext, object: anytype) !void {
    const abs_path = try PlatformUtils.SaveFile(engine_context.FrameAllocator(), ".imsc");
    if (abs_path.len > 0) {
        SerializeECSObject(self, engine_context, object, abs_path, .Text);
        const rel_path = engine_context.mAssetManager.GetRelPath(abs_path, .Prj);
        const asset_handle = try engine_context.mAssetManager.GetAssetHandle(engine_context, .{ .File = .{ .rel_path = rel_path, .path_type = .Prj } });
        self.mFileObjects.put(engine_context.EngineAllocator(), object.GetUUID(), asset_handle);
    }
}

fn SerializeECSObject(_: Serializer, engine_context: *EngineContext, object: anytype, abs_path: []const u8, comptime serialize_type: SerializeType) !void {
    switch (serialize_type) {
        .Text => TextSerializer.SerializeECSObject(engine_context, object, abs_path),
    }
}

pub fn DeserializeECSObj(self: Serializer, engine_context: *EngineContext, object: anytype, abs_path: []const u8, deserialize_type: SerializeType) !void {
    switch (deserialize_type) {
        .Text => TextSerializer.DeserializeECSObj(engine_context, object, abs_path),
    }

    const rel_path = engine_context.mAssetManager.GetRelPath(abs_path, .Prj);
    const asset_handle = try engine_context.mAssetManager.GetAssetHandle(engine_context, .{ .File = .{ .rel_path = rel_path, .path_type = .Prj } });
    self.mFileObjects.put(engine_context.EngineAllocator(), object.GetUUID(), asset_handle);
}

pub fn ResolveUUIDs(_: Serializer, engine_allocator: std.mem.Allocator, world_manager: *WorldManager) void {
    var front: usize = 0;
    var back: usize = scene_manager.mResolveUUIDList.items.len;

    while (front < back) {
        const request = scene_manager.mResolveUUIDList.items[front];

        const active = switch (request.Requester) {
            .Entity => |e| e.IsActive(),
            .Scene => |s| s.IsActive(),
            .Player => |p| p.IsActive(),
            .GameMode => |g| g.IsActive(),
        };

        if (!active) {
            scene_manager.mResolveUUIDList.items[front] = scene_manager.mResolveUUIDList.items[back - 1];
            back -= 1;
            continue;
        }

        if (scene_manager.GetWorldID(request.UUID)) |world_id| {
            switch (request.Requester) {
                .Entity => {
                    const set_loc: *Entity.Type = @ptrCast(@alignCast(request.SetLoc));
                    set_loc.* = @intCast(world_id);
                },
                .Scene => {
                    const set_loc: *SceneLayer.Type = @ptrCast(@alignCast(request.SetLoc));
                    set_loc.* = @intCast(world_id);
                },
                .Player => {
                    const set_loc: *Player.Type = @ptrCast(@alignCast(request.SetLoc));
                    set_loc.* = @intCast(world_id);
                },
                .GameMode => {
                    const set_loc: *GameMode.Type = @ptrCast(@alignCast(request.SetLoc));
                    set_loc.* = @intCast(world_id);
                },
            }
        }
        front += 1;
    }
    scene_manager.mResolveUUIDList.shrinkAndFree(engine_allocator, back);
}

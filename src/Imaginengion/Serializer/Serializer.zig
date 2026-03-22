const std = @import("std");
const SceneLayer = @import("../Scene/SceneLayer.zig");
const Entity = @import("../GameObjects/Entity.zig");

const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;

const Renderer = @import("../Renderer/Renderer.zig");

const EngineContext = @import("../Core/EngineContext.zig");

const WriteStream = std.json.Stringify;
const StringifyOptions = std.json.Stringify.Options{ .whitespace = .indent_2 };
const PARSE_OPTIONS = std.json.ParseOptions{ .allocate = .alloc_if_needed, .max_value_len = std.json.default_max_value_len };

const TextSerializer = @import("TextSerializer.zig");
const BinarySerializer = @import("BinarySerializer.zig");

var prng: std.Random.Xoshiro256 = undefined;
var random_init_once = std.once(random_init);

const Serializer = @This();

pub const empty: Serializer = .{
    .mResolveUUIDList = .empty,
    .mUUIDToWorldID = .empty,
};

pub const SerializeType = enum {
    Text,
    Binary,
};

pub const Requester = union(enum) {
    Entity: Entity,
    Scene: SceneLayer,
};

pub const ResolveReq = struct {
    Requester: Requester,
    UUID: u64,
    SetLoc: *anyopaque,
};

mResolveUUIDList: std.ArrayList(ResolveReq),
mUUIDToWorldID: std.AutoHashMapUnmanaged(u64, usize),

pub fn Deinit(self: Serializer, engine_allocator: std.mem.Allocator) void {
    self.mUUIDToWorldID.deinit(engine_allocator);
}

pub fn SerializeScene(_: Serializer, frame_allocator: std.mem.Allocator, scene_layer: SceneLayer, abs_path: []const u8, _: SerializeType) !void {
    TextSerializer.SerializeScene(frame_allocator, scene_layer, abs_path);
}

pub fn SerializeEntity(_: Serializer, frame_allocator: std.mem.Allocator, entity: Entity, abs_path: []const u8, _: SerializeType) !void {
    TextSerializer.SerializeEntity(frame_allocator, entity, abs_path);
}

pub fn DeserializeScene(self: Serializer, engine_context: *EngineContext, scene_layer: SceneLayer, abs_path: []const u8, _: SerializeType) !void {
    TextSerializer.DeserializeScene(engine_context, scene_layer, abs_path);
    self.ResolveUUIDs(engine_context.EngineAllocator());
}

pub fn DeserializeEntity(_: Serializer, engine_context: *EngineContext, scene_layer: SceneLayer, abs_path: []const u8) !void {
    TextSerializer.DeserializeEntity(engine_context, scene_layer, abs_path);
}

pub fn AddUUID(self: Serializer, engine_allocator: std.mem.Allocator, uuid: u64, world_id: usize) void {
    self.mUUIDToWorldID.put(engine_allocator, uuid, world_id);
}

pub fn RemoveUUID(self: Serializer, uuid: u64) void {
    _ = self.mUUIDToWorldID.remove(uuid);
}

pub fn CheckUUID(self: Serializer, uuid: u64) ?usize {
    return self.mUUIDToWorldID.get(uuid);
}

fn random_init() void {
    var seed: u64 = undefined;
    std.posix.getrandom(std.mem.asBytes(&seed)) catch unreachable;
    prng.seed(seed);
}

pub fn GenUUID() u64 {
    random_init_once.call();
    return prng.random().uintAtMost(u64, ~@as(u64, 0) - 1);
}

fn ResolveUUIDs(self: Serializer, engine_allocator: std.mem.Allocator) void {
    var front: usize = 0;
    var back: usize = self.mResolveUUIDList.items.len;

    while (front < back) {
        const request = self.mResolveUUIDList.items[front];

        const active = switch (request.Requester) {
            .Entity => |e| e.IsActive(),
            .Scene => |s| s.IsActive(),
        };

        if (!active) {
            self.mResolveUUIDList.items[front] = self.mResolveUUIDList.items[back - 1];
            back -= 1;
            continue;
        }

        if (self.CheckUUID(request.UUID)) |world_id| {
            switch (request.Requester) {
                .Entity => {
                    const set_loc: *Entity.Type = @ptrCast(@alignCast(request.SetLoc));
                    set_loc.* = world_id;
                },
                .Scene => {
                    const set_loc: *SceneLayer.Type = @ptrCast(@alignCast(request.SetLoc));
                    set_loc.* = world_id;
                },
            }
        }
        front += 1;
    }
    self.mResolveUUIDList.shrinkAndFree(engine_allocator, back);
}

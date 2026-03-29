const std = @import("std");
const SceneLayer = @import("../Scene/SceneLayer.zig");
const Entity = @import("../GameObjects/Entity.zig");

const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;

const Renderer = @import("../Renderer/Renderer.zig");

const once = @import("../Core/Once.zig").once;

const EngineContext = @import("../Core/EngineContext.zig");
const WorldType = EngineContext.WorldType;

const WriteStream = std.json.Stringify;
const StringifyOptions = std.json.Stringify.Options{ .whitespace = .indent_2 };
const PARSE_OPTIONS = std.json.ParseOptions{ .allocate = .alloc_if_needed, .max_value_len = std.json.default_max_value_len };

const SceneManager = @import("../Scene/SceneManager.zig");

const TextSerializer = @import("TextSerializer.zig");
const BinarySerializer = @import("BinarySerializer.zig");
var prng: std.Random.Xoshiro256 = undefined;
var random_init_once = once(random_init);

const Serializer = @This();

pub const SerializeType = enum {
    Text,
    Binary,
};

pub const Requester = union(enum(u16)) {
    Entity: Entity,
    Scene: SceneLayer,

    pub const default: Requester = .{ .Entity = .{} };
};

pub const ResolveReq = struct {
    Requester: Requester,
    UUID: u64,
    SetLoc: *anyopaque,
};

pub const DeserializeContext = struct {
    requester: Requester = Requester.default,
    component_ptr: *anyopaque = undefined,
};

pub const empty: Serializer = .{
    .mCurrDeserialize = DeserializeContext{},
};

mCurrDeserialize: DeserializeContext,

pub fn Deinit(_: Serializer, _: std.mem.Allocator) void {}

pub fn SerializeScene(_: Serializer, frame_allocator: std.mem.Allocator, scene_layer: SceneLayer, abs_path: []const u8, _: SerializeType) !void {
    try TextSerializer.SerializeScene(frame_allocator, scene_layer, abs_path);
}

pub fn SerializeEntity(_: Serializer, frame_allocator: std.mem.Allocator, entity: Entity, abs_path: []const u8, _: SerializeType) !void {
    try TextSerializer.SerializeEntity(frame_allocator, entity, abs_path);
}

pub fn DeserializeScene(self: Serializer, engine_context: *EngineContext, scene_layer: SceneLayer, abs_path: []const u8, _: SerializeType) !void {
    try TextSerializer.DeserializeScene(engine_context, scene_layer, abs_path);
    self.ResolveUUIDs(engine_context.EngineAllocator(), scene_layer.mSceneManager);
}

pub fn DeserializeEntity(_: Serializer, engine_context: *EngineContext, scene_layer: SceneLayer, abs_path: []const u8) !void {
    TextSerializer.DeserializeEntity(engine_context, scene_layer, abs_path);
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

pub fn ResolveUUIDs(_: Serializer, engine_allocator: std.mem.Allocator, scene_manager: *SceneManager) void {
    var front: usize = 0;
    var back: usize = scene_manager.mResolveUUIDList.items.len;

    while (front < back) {
        const request = scene_manager.mResolveUUIDList.items[front];

        const active = switch (request.Requester) {
            .Entity => |e| e.IsActive(),
            .Scene => |s| s.IsActive(),
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
            }
        }
        front += 1;
    }
    scene_manager.mResolveUUIDList.shrinkAndFree(engine_allocator, back);
}

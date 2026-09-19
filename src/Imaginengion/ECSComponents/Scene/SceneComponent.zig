const std = @import("std");
const ComponentsList = @import("../SceneComponents.zig").ComponentsList;
const Entity = @import("../../GameObjects/Entity.zig");
const ECSManagerScenes = @import("../../Core/WorldManager.zig").ECSManagerScenes;
const AssetHandle = @import("../../Assets/AssetHandle.zig");

const EngineContext = @import("../../Core/EngineContext.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const SceneComponent = @This();

pub const LayerType = enum(u1) {
    GameLayer = 0,
    OverlayLayer = 1,
};

pub const Name: []const u8 = "SceneComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == SceneComponent) {
            break :blk i + 5; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

mLayerType: LayerType = .GameLayer,

pub fn Deinit(_: *SceneComponent, _: *EngineContext) !void {}

const Json = JsonUtils.JsonFields(SceneComponent, .{ .LayerType = "mLayerType" });
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

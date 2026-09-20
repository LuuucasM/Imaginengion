const EngineContext = @import("../../Core/EngineContext.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const SceneComponent = @This();

pub const LayerType = enum(u1) {
    GameLayer = 0,
    OverlayLayer = 1,
};

pub const Name: []const u8 = "SceneComponent";

mLayerType: LayerType = .GameLayer,

pub fn Deinit(_: *SceneComponent, _: *EngineContext) void {}

const Json = JsonUtils.JsonFields(SceneComponent, .{ .LayerType = "mLayerType" });
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

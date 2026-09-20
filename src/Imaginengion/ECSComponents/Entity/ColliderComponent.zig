const std = @import("std");
const Vec3 = @import("../../Math/MathTypes.zig").Vec3;
const EngineContext = @import("../../Core/EngineContext.zig");
const ImguiManager = @import("../../Imgui/Imgui.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const CollisionFilter = @import("../../Physics/CollisionManager.zig").CollisionFilter;
const CollisionManager = @import("../../Physics/CollisionManager.zig");
const Entity = @import("../../ECSObjects/Entity.zig");

const ColliderComponent = @This();

pub const Shapes = enum {
    Box,
    Sphere,
};

pub const Editable: bool = true;
pub const Name: []const u8 = "ColliderComponent";

mShape: Shapes = .Sphere,
mCollisionFilter: CollisionFilter = .default,

pub fn Deinit(_: *ColliderComponent, _: *EngineContext) void {}

pub fn EditorRender(self: *ColliderComponent, _: *EngineContext) !void {
    try ImguiManager.RenderEnum(Shapes, &self.mShape, "Collider Type");
    try self.mCollisionFilter.ImguiRender();
}

const Json = JsonUtils.JsonFields(ColliderComponent, .{
    .Shape = "mShape",
    .CollisionFilter = "mCollisionFilter",
});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

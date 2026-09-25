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
//each shape's own size at scale 1, only the one for mShape is used. the defaults fit a default quad
mBoxSize: Vec3(f32) = .{ .x = 1, .y = 1, .z = 1 }, //full width, height and depth, like a quad's size
mRadius: f32 = 0.5,
mCollisionFilter: CollisionFilter = .default,

pub fn Deinit(_: *ColliderComponent, _: *EngineContext) void {}

/// The box's half extents in world units: its full size, grown by the transform's scale, halved.
pub fn GetWorldHalfExtents(self: ColliderComponent, world_scale: Vec3(f32)) Vec3(f32) {
    return self.mBoxSize.MulVec(world_scale).MulScalar(0.5);
}

/// The sphere's radius in world units. A sphere can only grow evenly, so it takes the largest scale axis.
pub fn GetWorldRadius(self: ColliderComponent, world_scale: Vec3(f32)) f32 {
    return self.mRadius * @max(world_scale.x, @max(world_scale.y, world_scale.z));
}

pub fn EditorRender(self: *ColliderComponent, _: *EngineContext) !void {
    try ImguiManager.RenderEnum(Shapes, &self.mShape, "Collider Type");
    switch (self.mShape) {
        .Box => try ImguiManager.RenderVec3(&self.mBoxSize, "Box Size", 1.0, 0.05, 100.0),
        .Sphere => _ = try ImguiManager.RenderFloatDrag(&self.mRadius, "Radius", 0.05, 0, std.math.floatMax(f32)),
    }
    try self.mCollisionFilter.ImguiRender();
}

const Json = JsonUtils.JsonFields(ColliderComponent, .{
    .Shape = "mShape",
    .BoxSize = "mBoxSize",
    .Radius = "mRadius",
    .CollisionFilter = "mCollisionFilter",
});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

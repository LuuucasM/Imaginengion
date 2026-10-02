const std = @import("std");
const Vec3 = @import("../../Math/MathTypes.zig").Vec3;
const EngineContext = @import("../../Core/EngineContext.zig");
const ImguiManager = @import("../../Imgui/Imgui.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const CollisionFilter = @import("../../Physics/CollisionManager.zig").CollisionFilter;
const CollisionManager = @import("../../Physics/CollisionManager.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const SDF = @import("../../Math/SDFFunctions.zig");

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

/// The collider's signed distance at a point in its own space: relative to its world position and unrotated
/// (SDF.GetLocalPoint), negative inside. The same SDF primitives the renderer draws shapes with. The shape's
/// size is grown by world_scale rather than the point being shrunk, so the distance stays a true distance
pub fn LocalDistance(self: ColliderComponent, local_point: Vec3(f32), world_scale: Vec3(f32)) f32 {
    return switch (self.mShape) {
        .Box => SDF.sdBox(local_point, self.GetWorldHalfExtents(world_scale)),
        .Sphere => SDF.sdSphere(local_point, self.GetWorldRadius(world_scale)),
    };
}

/// The direction out of the collider's surface at a point in its own space, the gradient of LocalDistance
pub fn LocalNormal(self: ColliderComponent, local_point: Vec3(f32), world_scale: Vec3(f32)) Vec3(f32) {
    return switch (self.mShape) {
        .Box => SDF.gradBox(local_point, self.GetWorldHalfExtents(world_scale)),
        .Sphere => SDF.gradSphere(local_point),
    };
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

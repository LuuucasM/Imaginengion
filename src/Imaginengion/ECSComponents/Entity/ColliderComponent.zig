const std = @import("std");
const Inspector = @import("../../UI/Inspector.zig");
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
//how far a box's edges and corners are rounded off, at scale 1. A sharp box catches on the seam between two
//boxes it slides over (two floor tiles side by side): resting on the first, the corner of the next is straight
//ahead of it, a wall. Rounded, the corner is a bump it rides over. A pair's roundings add up, so rounding the
//box that moves is enough, see GetWorldCornerRadius for how big
mCornerRadius: f32 = 0.0,
mCollisionFilter: CollisionFilter = .default,
//hand this collider's solid contacts to OnPreSolve scripts every substep before the solver acts on them, which can
//switch a contact off (e.g. a one way platform). Off by default, since that is a script call per contact per substep.
//Either collider of a pair asking is enough, and the scripts of both game objects are run
mPreSolveEvents: bool = false,

pub fn Deinit(_: *ColliderComponent, _: *EngineContext) void {}

/// The box's half extents in world units: its full size, grown by the transform's scale, halved.
pub fn GetWorldHalfExtents(self: ColliderComponent, world_scale: Vec3(f32)) Vec3(f32) {
    return self.mBoxSize.MulVec(world_scale).MulScalar(0.5);
}

/// The box's corner radius in world units: grown by the transform's smallest scale axis, since a rounding can only
/// grow evenly, and at most the smallest half extent, which rounds that side off completely.
/// It has to be well above CollisionManager's SLOP (0.01) to stop a box catching on a seam, since a resting body
/// sits up to that far into the floor and a rounding not much bigger is still mostly a wall ahead of it
pub fn GetWorldCornerRadius(self: ColliderComponent, world_scale: Vec3(f32)) f32 {
    const half_extents = self.GetWorldHalfExtents(world_scale);
    const smallest_half = @min(half_extents.x, @min(half_extents.y, half_extents.z));
    const radius = self.mCornerRadius * @min(world_scale.x, @min(world_scale.y, world_scale.z));
    return std.math.clamp(radius, 0.0, @max(smallest_half, 0.0));
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
        .Box => SDF.sdRoundedBox(local_point, self.GetWorldHalfExtents(world_scale), self.GetWorldCornerRadius(world_scale)),
        .Sphere => SDF.sdSphere(local_point, self.GetWorldRadius(world_scale)),
    };
}

/// The direction out of the collider's surface at a point in its own space, the gradient of LocalDistance
pub fn LocalNormal(self: ColliderComponent, local_point: Vec3(f32), world_scale: Vec3(f32)) Vec3(f32) {
    return switch (self.mShape) {
        .Box => SDF.normalRoundedBox(local_point, self.GetWorldHalfExtents(world_scale), self.GetWorldCornerRadius(world_scale)),
        .Sphere => SDF.gradSphere(local_point),
    };
}

pub fn UIRender(self: *ColliderComponent, ui: *Inspector.Builder) !void {
    //which shape it is decides which sizes there are
    try ui.Enum(Shapes, &self.mShape, "Shape", .{ .Rebuilds = true });
    switch (self.mShape) {
        .Box => {
            try ui.Vec3Field(&self.mBoxSize, "Box Size", .{ .Speed = 0.05, .Min = 0 });
            try ui.Float(&self.mCornerRadius, "Corner Radius", .{ .Speed = 0.01, .Min = 0 });
        },
        .Sphere => try ui.Float(&self.mRadius, "Radius", .{ .Speed = 0.05, .Min = 0 }),
    }
    try ui.Struct(&self.mCollisionFilter, "Collision Filter");
    try ui.Bool(&self.mPreSolveEvents, "Pre-Solve Events", .{});
}

pub fn EditorRender(self: *ColliderComponent, _: *EngineContext) !void {
    try ImguiManager.RenderEnum(Shapes, &self.mShape, "Collider Type");
    switch (self.mShape) {
        .Box => {
            try ImguiManager.RenderVec3(&self.mBoxSize, "Box Size", 1.0, 0.05, 100.0);
            _ = try ImguiManager.RenderFloatDrag(&self.mCornerRadius, "Corner Radius", 0.01, 0, std.math.floatMax(f32));
        },
        .Sphere => _ = try ImguiManager.RenderFloatDrag(&self.mRadius, "Radius", 0.05, 0, std.math.floatMax(f32)),
    }
    try self.mCollisionFilter.ImguiRender();
    try ImguiManager.RenderBool(&self.mPreSolveEvents, "Pre-Solve Events?");
}

const Json = JsonUtils.JsonFields(ColliderComponent, .{
    .Shape = "mShape",
    .BoxSize = "mBoxSize",
    .Radius = "mRadius",
    .CornerRadius = "mCornerRadius",
    .CollisionFilter = "mCollisionFilter",
    .PreSolveEvents = "mPreSolveEvents",
});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

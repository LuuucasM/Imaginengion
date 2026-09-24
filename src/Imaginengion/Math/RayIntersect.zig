const std = @import("std");
const MathTypes = @import("MathTypes.zig");
const CameraRay = @import("CameraRay.zig");
const Vec3 = MathTypes.Vec3;
const Quat = MathTypes.Quat;
const Ray = CameraRay.Ray;

pub const HitInfo = struct {
    T: f32, //distance along the ray, in world units since Ray.Dir is normalized. +inf on a miss
    Normal: Vec3(f32), //world space, facing back toward the ray
    StartedInside: bool, //the ray origin was inside the shape, T is 0 and Normal is -Dir

    //+inf rather than -inf so a miss always loses a "closest hit wins" comparison:
    //`if (hit.T < best.T) best = hit;` starting from `best = .miss` needs no special case
    pub const miss: HitInfo = .{
        .T = std.math.inf(f32),
        .Normal = .{ .x = 0, .y = 0, .z = 0 },
        .StartedInside = false,
    };

    pub fn IsHit(self: HitInfo) bool {
        return self.T != std.math.inf(f32);
    }
};

/// Ray against an oriented box, using the slab test. A ray that starts inside hits at T = 0,
/// the same as the SDF renderer, which treats a negative distance as an immediate hit.
pub fn RayBox(ray: Ray, center: Vec3(f32), rotation: Quat(f32), half_extents: Vec3(f32)) HitInfo {
    //in the box's own space it is axis aligned and centered on the origin
    const local_origin = ray.Origin.SubVec(center).InvQuatRotate(rotation).ToVector();
    const local_dir = ray.Dir.InvQuatRotate(rotation).ToVector();
    const half = half_extents.ToVector();

    //an axis the ray is parallel to divides by +-0 and gets +-inf, which makes that slab either
    //never constrain the ray (origin between its walls) or reject it (origin outside them).
    //a ray parallel to and exactly on a wall gives 0 * inf = NaN for that wall, which @min/@max
    //drop in favor of the other operand, so it comes out as a miss and never as a NaN T.
    const inv_dir = @as(Vec3(f32).VectorT, @splat(1.0)) / local_dir;
    const t_wall_neg = (-half - local_origin) * inv_dir;
    const t_wall_pos = (half - local_origin) * inv_dir;

    //per axis: when the ray enters and leaves that pair of walls. it is inside the box only while
    //it is inside all three, from the latest enter to the earliest leave
    const t_near = @min(t_wall_neg, t_wall_pos);
    const t_far = @max(t_wall_neg, t_wall_pos);
    const t_enter = @reduce(.Max, t_near);
    const t_exit = @reduce(.Min, t_far);

    if (t_enter > t_exit or t_exit < 0) return .miss;

    if (t_enter < 0) {
        return .{ .T = 0, .Normal = ray.Dir.Neg(), .StartedInside = true };
    }

    //the face that was entered through belongs to the axis whose enter time is the box's.
    //a parallel axis can't match, its enter time is +-inf and t_enter is finite here. an exact
    //edge or corner hit matches several axes, and normalizing blends their faces into the
    //edge's normal
    const zero: Vec3(f32).VectorT = @splat(0.0);
    const facing_back = @select(f32, local_dir > zero, @as(Vec3(f32).VectorT, @splat(-1.0)), @as(Vec3(f32).VectorT, @splat(1.0)));
    const local_normal = @select(f32, t_near == @as(Vec3(f32).VectorT, @splat(t_enter)), facing_back, zero);

    return .{
        .T = t_enter,
        .Normal = Vec3(f32).FromVector(local_normal).Dir().QuatRotate(rotation),
        .StartedInside = false,
    };
}

/// Ray against a sphere. Ray.Dir must be normalized, which CameraRay.MakeRay guarantees.
pub fn RaySphere(ray: Ray, center: Vec3(f32), radius: f32) HitInfo {
    if (radius <= 0) return .miss;

    //|origin + t*dir - center|^2 = radius^2 is a quadratic in t: t^2 + 2bt + c = 0
    const to_origin = ray.Origin.SubVec(center);
    const b = to_origin.Dot(ray.Dir);
    const c = to_origin.Dot(to_origin) - radius * radius;

    if (c < 0) {
        return .{ .T = 0, .Normal = ray.Dir.Neg(), .StartedInside = true };
    }

    //outside and pointing away
    if (b > 0) return .miss;

    const discriminant = b * b - c;
    if (discriminant < 0) return .miss;

    const t = -b - @sqrt(discriminant);
    const point = ray.Origin.AddVec(ray.Dir.MulScalar(t));

    return .{
        .T = t,
        .Normal = point.SubVec(center).DivScalar(radius),
        .StartedInside = false,
    };
}

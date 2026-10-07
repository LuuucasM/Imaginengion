//! An axis aligned bounding box: the smallest box lined up with the world axes that holds a shape. What a BVH is
//! built from and tested against, since a ray against one is a few comparisons. Each primitive's own is worked out
//! by its aabb function in SDFFunctions (aabbBox, aabbIMQuad...), next to its sd and ray ones.
const MathTypes = @import("MathTypes.zig");
const Vec3 = MathTypes.Vec3;
const inf = @import("std").math.inf(f32);

const Aabb = @This();

Min: Vec3(f32),
Max: Vec3(f32),

/// Holds nothing, and Union with it gives back the other box: where a box grown over several shapes starts from
pub const empty: Aabb = .{
    .Min = .{ .x = inf, .y = inf, .z = inf },
    .Max = .{ .x = -inf, .y = -inf, .z = -inf },
};

/// The smallest box holding both
pub fn Union(a: Aabb, b: Aabb) Aabb {
    return .{
        .Min = .FromVector(@min(a.Min.ToVector(), b.Min.ToVector())),
        .Max = .FromVector(@max(a.Max.ToVector(), b.Max.ToVector())),
    };
}

pub fn Center(self: Aabb) Vec3(f32) {
    return self.Min.AddVec(self.Max).MulScalar(0.5);
}

/// Whether `point` is inside or on the box
pub fn Contains(self: Aabb, point: Vec3(f32)) bool {
    return point.x >= self.Min.x and point.y >= self.Min.y and point.z >= self.Min.z and
        point.x <= self.Max.x and point.y <= self.Max.y and point.z <= self.Max.z;
}

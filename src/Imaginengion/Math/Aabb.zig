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

/// The box pushed out by `amount` on every side
pub fn Grow(self: Aabb, amount: f32) Aabb {
    const reach = Vec3(f32){ .x = amount, .y = amount, .z = amount };
    return .{ .Min = self.Min.SubVec(reach), .Max = self.Max.AddVec(reach) };
}

/// Whether the two share any point, edges touching included. Where they share is from the later of the two mins to the
/// earlier of the two maxes along each axis, so they overlap if that is not empty along any of them: one compare for
/// all three axes, with no branch per axis
pub fn Overlaps(a: Aabb, b: Aabb) bool {
    return @reduce(.And, @max(a.Min.ToVector(), b.Min.ToVector()) <= @min(a.Max.ToVector(), b.Max.ToVector()));
}

pub fn Center(self: Aabb) Vec3(f32) {
    return self.Min.AddVec(self.Max).MulScalar(0.5);
}

/// Half the box's surface area. A ray from anywhere through a bigger box around it goes through this one with a chance
/// in proportion to its surface area, which is what a BVH build weighs boxes by; only ever compared, so half does. A
/// flat box still has the area of its face. Not for the empty box
pub fn HalfArea(self: Aabb) f32 {
    const size = self.Max.SubVec(self.Min);
    return size.x * size.y + size.y * size.z + size.z * size.x;
}

/// Whether `point` is inside or on the box
pub fn Contains(self: Aabb, point: Vec3(f32)) bool {
    const p = point.ToVector();
    return @reduce(.And, p >= self.Min.ToVector()) and @reduce(.And, p <= self.Max.ToVector());
}

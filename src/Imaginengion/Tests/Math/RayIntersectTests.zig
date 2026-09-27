const std = @import("std");
const MathTypes = @import("../../Math/MathTypes.zig");
const RayIntersect = @import("../../Math/RayIntersect.zig");
const Ray = @import("../../Math/CameraRay.zig").Ray;
const Vec2 = MathTypes.Vec2;
const Vec3 = MathTypes.Vec3;
const Vec4 = MathTypes.Vec4;
const Quat = MathTypes.Quat;

const eps: f32 = 0.0001;

//SDFFunctions.THICKNESS_2D, not imported because SDFFunctions pulls in the renderer
const THICKNESS_2D: f32 = 0.001;

const ORIGIN = Vec3(f32){ .x = 0, .y = 0, .z = 0 };
const IDENTITY = Quat(f32){ .w = 1, .x = 0, .y = 0, .z = 0 };
const UNIT_HALF = Vec3(f32){ .x = 1, .y = 1, .z = 1 };

fn MakeRay(origin: Vec3(f32), dir: Vec3(f32)) Ray {
    return .{ .Origin = origin, .Dir = dir.Dir() };
}

fn ExpectVec3(expected: Vec3(f32), actual: Vec3(f32)) !void {
    try std.testing.expectApproxEqAbs(expected.x, actual.x, eps);
    try std.testing.expectApproxEqAbs(expected.y, actual.y, eps);
    try std.testing.expectApproxEqAbs(expected.z, actual.z, eps);
}

fn ExpectNoNaN(hit: RayIntersect.HitInfo) !void {
    try std.testing.expect(!std.math.isNan(hit.T));
    try std.testing.expect(!std.math.isNan(hit.Normal.x) and !std.math.isNan(hit.Normal.y) and !std.math.isNan(hit.Normal.z));
}

//mirrors SDFFunctions.sdBox, the distance the GPU marches against
fn sdBox(point: Vec3(f32), half_extents: Vec3(f32)) f32 {
    const q = point.Abs().SubVec(half_extents);
    return q.ClampScalar(0).Len() + @min(@max(q.x, @max(q.y, q.z)), 0.0);
}

//==================================RayBox==================================

test "RayBox straight at the front face" {
    const hit = RayIntersect.RayBox(MakeRay(.{ .x = 0, .y = 0, .z = 5 }, .{ .x = 0, .y = 0, .z = -1 }), ORIGIN, IDENTITY, UNIT_HALF);
    try std.testing.expect(hit.IsHit());
    try std.testing.expectApproxEqAbs(@as(f32, 4), hit.T, eps);
    try ExpectVec3(.{ .x = 0, .y = 0, .z = 1 }, hit.Normal);
    try std.testing.expect(!hit.StartedInside);
}

test "RayBox rotated 45 degrees hits the corner edge" {
    const rotation = Quat(f32).FromAxisAngle(.{ .x = 0, .y = 1, .z = 0 }, std.math.degreesToRadians(45.0));
    const hit = RayIntersect.RayBox(MakeRay(.{ .x = 0, .y = 0, .z = 5 }, .{ .x = 0, .y = 0, .z = -1 }), ORIGIN, rotation, UNIT_HALF);
    try std.testing.expect(hit.IsHit());
    //the edge sits sqrt(2) in front of the center
    try std.testing.expectApproxEqAbs(5 - std.math.sqrt2, hit.T, eps);
    //one of the two faces meeting at the edge (leaning 45 degrees toward the ray), or their blend
    //(pointing straight back) if rounding makes both enter times exactly equal
    try std.testing.expectApproxEqAbs(@as(f32, 1), hit.Normal.Len(), eps);
    try std.testing.expect(hit.Normal.z >= 0.70710677 - eps);
    try std.testing.expectApproxEqAbs(@as(f32, 0), hit.Normal.y, eps);
}

test "RayBox exactly on an edge blends the two faces" {
    //both slab computations are bit-identical, so both axes enter at exactly the same t
    const hit = RayIntersect.RayBox(MakeRay(.{ .x = 2, .y = 2, .z = 0 }, .{ .x = -1, .y = -1, .z = 0 }), ORIGIN, IDENTITY, UNIT_HALF);
    try std.testing.expect(hit.IsHit());
    try std.testing.expectApproxEqAbs(std.math.sqrt2, hit.T, eps);
    try ExpectVec3(.{ .x = 0.70710677, .y = 0.70710677, .z = 0 }, hit.Normal);
}

test "RayBox parallel with a negative zero direction component" {
    //-0 divides to -inf instead of +inf, the slab still has to be handled the same way
    const hit = RayIntersect.RayBox(.{ .Origin = .{ .x = 5, .y = 0.5, .z = 0.5 }, .Dir = .{ .x = -1, .y = -0.0, .z = -0.0 } }, ORIGIN, IDENTITY, UNIT_HALF);
    try std.testing.expect(hit.IsHit());
    try std.testing.expectApproxEqAbs(@as(f32, 4), hit.T, eps);
    try ExpectVec3(.{ .x = 1, .y = 0, .z = 0 }, hit.Normal);

    try std.testing.expect(!RayIntersect.RayBox(.{ .Origin = .{ .x = 5, .y = 1.5, .z = 0 }, .Dir = .{ .x = -1, .y = -0.0, .z = -0.0 } }, ORIGIN, IDENTITY, UNIT_HALF).IsHit());
}

test "a miss loses every closest hit comparison" {
    const hit = RayIntersect.RayBox(MakeRay(.{ .x = 0, .y = 0, .z = 5 }, .{ .x = 0, .y = 0, .z = -1 }), ORIGIN, IDENTITY, UNIT_HALF);
    try std.testing.expect(hit.T < RayIntersect.HitInfo.miss.T);
    try std.testing.expect(!RayIntersect.HitInfo.miss.IsHit());
}

test "RayBox beside the box misses" {
    try std.testing.expect(!RayIntersect.RayBox(MakeRay(.{ .x = 2, .y = 0, .z = 5 }, .{ .x = 0, .y = 0, .z = -1 }), ORIGIN, IDENTITY, UNIT_HALF).IsHit());
}

test "RayBox parallel to a face outside the box misses" {
    try std.testing.expect(!RayIntersect.RayBox(MakeRay(.{ .x = -5, .y = 1.5, .z = 0 }, .{ .x = 1, .y = 0, .z = 0 }), ORIGIN, IDENTITY, UNIT_HALF).IsHit());
}

test "RayBox parallel and exactly on a wall is a clean miss" {
    //0 * inf = NaN for that wall, @min/@max drop it, and the ray skimming the face counts as a miss.
    //both zero signs, since they send the NaN's partner to opposite infinities
    const on_wall_pos = RayIntersect.RayBox(MakeRay(.{ .x = -5, .y = 1, .z = 0 }, .{ .x = 1, .y = 0, .z = 0 }), ORIGIN, IDENTITY, UNIT_HALF);
    try std.testing.expect(!on_wall_pos.IsHit());
    try std.testing.expect(!std.math.isNan(on_wall_pos.T));

    const on_wall_neg = RayIntersect.RayBox(.{ .Origin = .{ .x = -5, .y = 1, .z = 0 }, .Dir = .{ .x = 1, .y = -0.0, .z = 0 } }, ORIGIN, IDENTITY, UNIT_HALF);
    try std.testing.expect(!on_wall_neg.IsHit());
    try std.testing.expect(!std.math.isNan(on_wall_neg.T));
}

test "RayBox behind the ray misses" {
    try std.testing.expect(!RayIntersect.RayBox(MakeRay(.{ .x = 0, .y = 0, .z = 5 }, .{ .x = 0, .y = 0, .z = 1 }), ORIGIN, IDENTITY, UNIT_HALF).IsHit());
}

test "RayBox starting inside hits at zero" {
    const dir = Vec3(f32){ .x = 0, .y = 0, .z = -1 };
    const hit = RayIntersect.RayBox(MakeRay(.{ .x = 0.2, .y = -0.3, .z = 0.5 }, dir), ORIGIN, IDENTITY, UNIT_HALF);
    try std.testing.expect(hit.IsHit());
    try std.testing.expect(hit.StartedInside);
    try std.testing.expectEqual(@as(f32, 0), hit.T);
    try ExpectVec3(dir.Neg(), hit.Normal);
}

test "RayBox thin quad head on" {
    const quad_half = Vec3(f32){ .x = 1, .y = 1, .z = THICKNESS_2D };
    const hit = RayIntersect.RayBox(MakeRay(.{ .x = 0.5, .y = 0.5, .z = 5 }, .{ .x = 0, .y = 0, .z = -1 }), ORIGIN, IDENTITY, quad_half);
    try std.testing.expect(hit.IsHit());
    try std.testing.expectApproxEqAbs(5 - THICKNESS_2D, hit.T, eps);
    try ExpectVec3(.{ .x = 0, .y = 0, .z = 1 }, hit.Normal);
}

test "RayBox thin quad edge on" {
    const quad_half = Vec3(f32){ .x = 1, .y = 1, .z = THICKNESS_2D };
    const dir = Vec3(f32){ .x = -1, .y = 0, .z = 0 };

    const hit = RayIntersect.RayBox(MakeRay(.{ .x = 5, .y = 0, .z = 0 }, dir), ORIGIN, IDENTITY, quad_half);
    try std.testing.expect(hit.IsHit());
    try std.testing.expectApproxEqAbs(@as(f32, 4), hit.T, eps);
    try ExpectVec3(.{ .x = 1, .y = 0, .z = 0 }, hit.Normal);

    //just outside the thickness
    try std.testing.expect(!RayIntersect.RayBox(MakeRay(.{ .x = 5, .y = 0, .z = THICKNESS_2D * 2 }, dir), ORIGIN, IDENTITY, quad_half).IsHit());
}

test "RayBox hit points lie on the surface the renderer marches" {
    var prng = std.Random.DefaultPrng.init(0x1A2B3C4D);
    const random = prng.random();

    var hits: usize = 0;
    for (0..500) |_| {
        const center = Vec3(f32){ .x = random.float(f32) * 10 - 5, .y = random.float(f32) * 10 - 5, .z = random.float(f32) * 10 - 5 };
        const axis = Vec3(f32){ .x = random.float(f32) - 0.5, .y = random.float(f32) - 0.5, .z = random.float(f32) - 0.5 };
        const rotation = Quat(f32).FromAxisAngle(axis.Dir(), random.float(f32) * std.math.tau);
        const half = Vec3(f32){ .x = 0.2 + random.float(f32) * 2, .y = 0.2 + random.float(f32) * 2, .z = 0.2 + random.float(f32) * 2 };

        //start somewhere on a shell around the box, aimed roughly at it
        const offset = Vec3(f32){ .x = random.float(f32) - 0.5, .y = random.float(f32) - 0.5, .z = random.float(f32) - 0.5 };
        const origin = center.AddVec(offset.Dir().MulScalar(15));
        const jitter = Vec3(f32){ .x = random.float(f32) * 4 - 2, .y = random.float(f32) * 4 - 2, .z = random.float(f32) * 4 - 2 };
        const ray = MakeRay(origin, center.AddVec(jitter).SubVec(origin));

        const hit = RayIntersect.RayBox(ray, center, rotation, half);
        if (!hit.IsHit()) continue;
        hits += 1;

        const world_point = ray.Origin.AddVec(ray.Dir.MulScalar(hit.T));
        const local_point = world_point.SubVec(center).InvQuatRotate(rotation);
        try std.testing.expectApproxEqAbs(@as(f32, 0), sdBox(local_point, half), 0.001);
        try std.testing.expectApproxEqAbs(@as(f32, 1), hit.Normal.Len(), eps);
        //the normal faces back toward where the ray came from
        try std.testing.expect(hit.Normal.Dot(ray.Dir) <= 0);

        //and it leaves through the surface too, no earlier than it came in
        const exit_point = ray.Origin.AddVec(ray.Dir.MulScalar(hit.TExit)).SubVec(center).InvQuatRotate(rotation);
        try std.testing.expectApproxEqAbs(@as(f32, 0), sdBox(exit_point, half), 0.001);
        try std.testing.expect(hit.TExit >= hit.T);
    }
    //the jitter is small enough that most rays should land, or this test proves nothing
    try std.testing.expect(hits > 100);
}

//==================================RaySphere==================================

test "RaySphere straight on" {
    const hit = RayIntersect.RaySphere(MakeRay(.{ .x = 0, .y = 0, .z = 5 }, .{ .x = 0, .y = 0, .z = -1 }), ORIGIN, 1);
    try std.testing.expect(hit.IsHit());
    try std.testing.expectApproxEqAbs(@as(f32, 4), hit.T, eps);
    try ExpectVec3(.{ .x = 0, .y = 0, .z = 1 }, hit.Normal);
    try std.testing.expect(!hit.StartedInside);
}

test "RaySphere grazing the side hits near the tangent point" {
    const hit = RayIntersect.RaySphere(MakeRay(.{ .x = 0.999, .y = 0, .z = 5 }, .{ .x = 0, .y = 0, .z = -1 }), ORIGIN, 1);
    try std.testing.expect(hit.IsHit());
    try ExpectNoNaN(hit);
    //tangent point is at z = 0, the chord is short enough that the hit is within ~0.05 of it
    try std.testing.expectApproxEqAbs(@as(f32, 5), hit.T, 0.05);
}

test "RaySphere just past the side misses" {
    try std.testing.expect(!RayIntersect.RaySphere(MakeRay(.{ .x = 1.001, .y = 0, .z = 5 }, .{ .x = 0, .y = 0, .z = -1 }), ORIGIN, 1).IsHit());
}

test "RaySphere behind the ray misses" {
    try std.testing.expect(!RayIntersect.RaySphere(MakeRay(.{ .x = 0, .y = 0, .z = 5 }, .{ .x = 0, .y = 0, .z = 1 }), ORIGIN, 1).IsHit());
}

test "RaySphere starting inside hits at zero" {
    const dir = Vec3(f32){ .x = 1, .y = 0, .z = 0 };
    const hit = RayIntersect.RaySphere(MakeRay(.{ .x = 0.1, .y = 0.2, .z = 0 }, dir), ORIGIN, 1);
    try std.testing.expect(hit.IsHit());
    try std.testing.expect(hit.StartedInside);
    try std.testing.expectEqual(@as(f32, 0), hit.T);
    try ExpectVec3(dir.Neg(), hit.Normal);
}

test "RaySphere with no radius never hits" {
    try std.testing.expect(!RayIntersect.RaySphere(MakeRay(.{ .x = 0, .y = 0, .z = 5 }, .{ .x = 0, .y = 0, .z = -1 }), ORIGIN, 0).IsHit());
}

test "RaySphere reports where it leaves" {
    const outside = RayIntersect.RaySphere(MakeRay(.{ .x = 0, .y = 0, .z = 5 }, .{ .x = 0, .y = 0, .z = -1 }), ORIGIN, 1);
    try std.testing.expectApproxEqAbs(@as(f32, 6), outside.TExit, eps);

    const inside = RayIntersect.RaySphere(MakeRay(.{ .x = 0, .y = 0, .z = 0 }, .{ .x = 1, .y = 0, .z = 0 }), ORIGIN, 1);
    try std.testing.expectApproxEqAbs(@as(f32, 1), inside.TExit, eps);
}

//==================================RayBox faces==================================

test "RayBox front face is PosZ with the quad texture's UV" {
    const hit = RayIntersect.RayBox(MakeRay(.{ .x = 0.5, .y = 0.5, .z = 5 }, .{ .x = 0, .y = 0, .z = -1 }), ORIGIN, IDENTITY, UNIT_HALF);
    try std.testing.expectApproxEqAbs(@as(f32, 4), hit.T, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 6), hit.TExit, eps);
    try std.testing.expectEqual(RayIntersect.BoxFace.PosZ, hit.Face.?);
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), hit.UV.x, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), hit.UV.y, eps);
}

test "RayBox faces use iq's index and UV axes" {
    //X faces take (y, z) as UV
    const neg_x = RayIntersect.RayBox(MakeRay(.{ .x = -5, .y = 0.5, .z = -0.5 }, .{ .x = 1, .y = 0, .z = 0 }), ORIGIN, IDENTITY, UNIT_HALF);
    try std.testing.expectEqual(RayIntersect.BoxFace.NegX, neg_x.Face.?);
    try std.testing.expectEqual(@as(u3, 0), @intFromEnum(neg_x.Face.?));
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), neg_x.UV.x, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), neg_x.UV.y, eps);

    //Y faces take (z, x)
    const pos_y = RayIntersect.RayBox(MakeRay(.{ .x = 0.5, .y = 5, .z = -0.5 }, .{ .x = 0, .y = -1, .z = 0 }), ORIGIN, IDENTITY, UNIT_HALF);
    try std.testing.expectEqual(RayIntersect.BoxFace.PosY, pos_y.Face.?);
    try std.testing.expectEqual(@as(u3, 3), @intFromEnum(pos_y.Face.?));
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), pos_y.UV.x, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), pos_y.UV.y, eps);

    const neg_z = RayIntersect.RayBox(MakeRay(.{ .x = 0, .y = 0, .z = -5 }, .{ .x = 0, .y = 0, .z = 1 }), ORIGIN, IDENTITY, UNIT_HALF);
    try std.testing.expectEqual(RayIntersect.BoxFace.NegZ, neg_z.Face.?);
}

test "RayBox face follows the box's rotation" {
    //a quarter turn about y brings the box's +Z face round to face +X
    const rotation = Quat(f32).FromAxisAngle(.{ .x = 0, .y = 1, .z = 0 }, std.math.pi / 2.0);
    const hit = RayIntersect.RayBox(MakeRay(.{ .x = 5, .y = 0, .z = 0 }, .{ .x = -1, .y = 0, .z = 0 }), ORIGIN, rotation, .{ .x = 1, .y = 1, .z = 2 });
    try std.testing.expectEqual(RayIntersect.BoxFace.PosZ, hit.Face.?);
    try std.testing.expectApproxEqAbs(@as(f32, 3), hit.T, eps);
}

test "RayBox starting inside has no face but still an exit" {
    const hit = RayIntersect.RayBox(MakeRay(.{ .x = 0, .y = 0, .z = 0 }, .{ .x = 1, .y = 0, .z = 0 }), ORIGIN, IDENTITY, .{ .x = 1, .y = 2, .z = 3 });
    try std.testing.expect(hit.StartedInside);
    try std.testing.expect(hit.Face == null);
    try std.testing.expectApproxEqAbs(@as(f32, 1), hit.TExit, eps);
}

//==================================RayRoundedBox==================================

//mirrors SDFFunctions.sdRoundedBox
fn sdRoundedBox(point: Vec3(f32), half_extents: Vec3(f32), radius: f32) f32 {
    return sdBox(point, half_extents.SubVec(.FromScalar(radius))) - radius;
}

const ROUND: f32 = 0.25;

test "RayRoundedBox straight at a flat face" {
    const hit = RayIntersect.RayRoundedBox(MakeRay(.{ .x = 0, .y = 0, .z = 5 }, .{ .x = 0, .y = 0, .z = -1 }), ORIGIN, IDENTITY, UNIT_HALF, ROUND);
    try std.testing.expectApproxEqAbs(@as(f32, 4), hit.T, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 6), hit.TExit, eps);
    try ExpectVec3(.{ .x = 0, .y = 0, .z = 1 }, hit.Normal);
    try std.testing.expect(!hit.StartedInside);
}

test "RayRoundedBox straight at a corner hits the corner sphere" {
    const s3 = @sqrt(@as(f32, 3));
    const hit = RayIntersect.RayRoundedBox(MakeRay(.{ .x = 5, .y = 5, .z = 5 }, .{ .x = -1, .y = -1, .z = -1 }), ORIGIN, IDENTITY, UNIT_HALF, ROUND);
    //the inner corner is at 0.75 on each axis, the surface a radius past it
    try std.testing.expectApproxEqAbs(5 * s3 - (0.75 * s3 + ROUND), hit.T, eps);
    try std.testing.expectApproxEqAbs(5 * s3 + (0.75 * s3 + ROUND), hit.TExit, eps);
    try ExpectVec3(.{ .x = 1 / s3, .y = 1 / s3, .z = 1 / s3 }, hit.Normal);
}

test "RayRoundedBox side of an edge hits the edge cylinder" {
    const hit = RayIntersect.RayRoundedBox(MakeRay(.{ .x = 0.9, .y = 5, .z = 0 }, .{ .x = 0, .y = -1, .z = 0 }), ORIGIN, IDENTITY, UNIT_HALF, ROUND);
    try std.testing.expectApproxEqAbs(@as(f32, 4.05), hit.T, eps);
    try ExpectVec3(.{ .x = 0.6, .y = 0.8, .z = 0 }, hit.Normal);
}

test "RayRoundedBox misses the corner a plain box would clip" {
    const ray = MakeRay(.{ .x = 0.95, .y = 0.95, .z = 5 }, .{ .x = 0, .y = 0, .z = -1 });
    try std.testing.expect(RayIntersect.RayBox(ray, ORIGIN, IDENTITY, UNIT_HALF).IsHit());
    try std.testing.expect(!RayIntersect.RayRoundedBox(ray, ORIGIN, IDENTITY, UNIT_HALF, ROUND).IsHit());
}

test "RayRoundedBox starting in a cut off corner is outside" {
    //inside the plain box but past the rounding, then across into the edge
    const hit = RayIntersect.RayRoundedBox(MakeRay(.{ .x = 0.95, .y = 0.95, .z = 0 }, .{ .x = -1, .y = 0, .z = 0 }), ORIGIN, IDENTITY, UNIT_HALF, ROUND);
    try std.testing.expect(!hit.StartedInside);
    try std.testing.expectApproxEqAbs(@as(f32, 0.05), hit.T, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 1.85), hit.TExit, eps);
    try ExpectVec3(.{ .x = 0.6, .y = 0.8, .z = 0 }, hit.Normal);
}

test "RayRoundedBox starting inside hits at zero" {
    const hit = RayIntersect.RayRoundedBox(MakeRay(.{ .x = 0, .y = 0, .z = 0 }, .{ .x = 1, .y = 0, .z = 0 }), ORIGIN, IDENTITY, UNIT_HALF, ROUND);
    try std.testing.expect(hit.StartedInside);
    try std.testing.expectEqual(@as(f32, 0), hit.T);
    try std.testing.expectApproxEqAbs(@as(f32, 1), hit.TExit, eps);
}

test "RayRoundedBox follows an edge over into the next octant" {
    //the case the sphere tracing test found: it enters the bounds beside the y edge just above y = 0,
    //runs along it, and hits the corner below. iq's version only tries the corners above and misses
    const half = Vec3(f32){ .x = 2.1956358, .y = 0.58141595, .z = 0.7963134 };
    const ray = MakeRay(.{ .x = -6.422632, .y = 4.624657, .z = -1.1671921 }, .{ .x = 0.67499256, .y = -0.73395646, .z = 0.07545094 });
    const hit = RayIntersect.RayRoundedBox(ray, ORIGIN, IDENTITY, half, 0.47979534);
    try std.testing.expect(hit.IsHit());
    try std.testing.expect(ray.Origin.AddVec(ray.Dir.MulScalar(hit.T)).y < 0);
}

test "RayRoundedBox with no rounding is RayBox" {
    const ray = MakeRay(.{ .x = 0.5, .y = 0.5, .z = 5 }, .{ .x = 0, .y = 0, .z = -1 });
    const plain = RayIntersect.RayBox(ray, ORIGIN, IDENTITY, UNIT_HALF);
    const rounded = RayIntersect.RayRoundedBox(ray, ORIGIN, IDENTITY, UNIT_HALF, 0);
    try std.testing.expectEqual(plain.T, rounded.T);
    try ExpectVec3(plain.Normal, rounded.Normal);
}

/// Sphere traces the rounded box, as a check on the analytic version that shares none of its octant logic.
fn MarchRoundedBox(origin: Vec3(f32), dir: Vec3(f32), half: Vec3(f32), radius: f32) f32 {
    var t: f32 = 0;
    for (0..4000) |_| {
        const d = sdRoundedBox(origin.AddVec(dir.MulScalar(t)), half, radius);
        if (d < 0.00001) return t;
        t += d;
        if (t > 100) break;
    }
    return std.math.inf(f32);
}

test "RayRoundedBox agrees with sphere tracing" {
    var prng = std.Random.DefaultPrng.init(0x20CDB0C5);
    const random = prng.random();

    var hits: usize = 0;
    var gap_starts: usize = 0;
    for (0..2000) |n| {
        const half = Vec3(f32){ .x = 0.2 + random.float(f32) * 2, .y = 0.2 + random.float(f32) * 2, .z = 0.2 + random.float(f32) * 2 };
        const radius = random.float(f32) * @min(half.x, @min(half.y, half.z));

        //half from a shell around the box, half from inside the plain box's bounds, which are the
        //rays that can start in a cut off corner
        const origin = if (n % 2 == 0) blk: {
            const offset = Vec3(f32){ .x = random.float(f32) - 0.5, .y = random.float(f32) - 0.5, .z = random.float(f32) - 0.5 };
            break :blk offset.Dir().MulScalar(8);
        } else Vec3(f32){
            .x = (random.float(f32) * 2 - 1) * half.x,
            .y = (random.float(f32) * 2 - 1) * half.y,
            .z = (random.float(f32) * 2 - 1) * half.z,
        };
        if (sdRoundedBox(origin, half, radius) <= 0.001) continue;
        if (n % 2 == 1) gap_starts += 1;

        const target = Vec3(f32){ .x = random.float(f32) * 3 - 1.5, .y = random.float(f32) * 3 - 1.5, .z = random.float(f32) * 3 - 1.5 };
        const ray = MakeRay(origin, target.SubVec(origin));

        const hit = RayIntersect.RayRoundedBox(ray, ORIGIN, IDENTITY, half, radius);
        const marched = MarchRoundedBox(ray.Origin, ray.Dir, half, radius);

        if (!hit.IsHit()) {
            //only a graze may be missed: the tracer can land within its epsilon of a surface the ray never enters
            if (marched != std.math.inf(f32)) {
                try std.testing.expect(sdRoundedBox(ray.Origin.AddVec(ray.Dir.MulScalar(marched + 0.01)), half, radius) > -0.001);
            }
            continue;
        }
        hits += 1;
        try ExpectNoNaN(hit);

        const point = ray.Origin.AddVec(ray.Dir.MulScalar(hit.T));
        const exit_point = ray.Origin.AddVec(ray.Dir.MulScalar(hit.TExit));
        try std.testing.expectApproxEqAbs(@as(f32, 0), sdRoundedBox(point, half, radius), 0.001);
        try std.testing.expectApproxEqAbs(@as(f32, 0), sdRoundedBox(exit_point, half, radius), 0.001);
        try std.testing.expect(hit.TExit >= hit.T);
        try std.testing.expectApproxEqAbs(@as(f32, 1), hit.Normal.Len(), eps);
        try std.testing.expect(hit.Normal.Dot(ray.Dir) <= 0.0001);

        if (marched == std.math.inf(f32)) {
            //the reverse: a graze the tracer stepped past, the middle of it barely inside
            const middle = ray.Origin.AddVec(ray.Dir.MulScalar((hit.T + hit.TExit) / 2));
            try std.testing.expect(sdRoundedBox(middle, half, radius) > -0.001);
        } else if (-hit.Normal.Dot(ray.Dir) > 0.1) {
            try std.testing.expectApproxEqAbs(marched, hit.T, 0.001);
        } else {
            //grazing, the tracer gets within its epsilon well before the ray goes in. it never oversteps though
            try std.testing.expect(marched <= hit.T + 0.001);
        }
    }
    try std.testing.expect(hits > 300);
    try std.testing.expect(gap_starts > 20);
}

//==================================RayRoundedBox2D==================================

//mirrors SDFFunctions.sdRoundedBox2D and opExtrusion
fn sdRoundedBox2DExtruded(point: Vec3(f32), half: Vec3(f32), radii: Vec4(f32)) f32 {
    const r = if (point.x > 0) (if (point.y > 0) radii.x else radii.y) else (if (point.y > 0) radii.z else radii.w);
    const qx = @abs(point.x) - half.x + r;
    const qy = @abs(point.y) - half.y + r;
    const d2 = @min(@max(qx, qy), 0) + (Vec2(f32){ .x = @max(qx, 0), .y = @max(qy, 0) }).Len() - r;
    const wz = @abs(point.z) - half.z;
    return @min(@max(d2, wz), 0) + (Vec2(f32){ .x = @max(d2, 0), .y = @max(wz, 0) }).Len();
}

const QUAD_HALF = Vec3(f32){ .x = 1, .y = 1, .z = THICKNESS_2D };
const ALL_ROUND = Vec4(f32){ .x = 0.25, .y = 0.25, .z = 0.25, .w = 0.25 };

test "RayRoundedBox2D front face is PosZ with the quad texture's UV" {
    const hit = RayIntersect.RayRoundedBox2D(MakeRay(.{ .x = 0.5, .y = 0.5, .z = 5 }, .{ .x = 0, .y = 0, .z = -1 }), ORIGIN, IDENTITY, QUAD_HALF, ALL_ROUND);
    try std.testing.expectApproxEqAbs(5 - THICKNESS_2D, hit.T, eps);
    try std.testing.expectApproxEqAbs(5 + THICKNESS_2D, hit.TExit, eps);
    try ExpectVec3(.{ .x = 0, .y = 0, .z = 1 }, hit.Normal);
    try std.testing.expectEqual(RayIntersect.BoxFace.PosZ, hit.Face.?);
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), hit.UV.x, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), hit.UV.y, eps);

    const back = RayIntersect.RayRoundedBox2D(MakeRay(.{ .x = 0, .y = 0, .z = -5 }, .{ .x = 0, .y = 0, .z = 1 }), ORIGIN, IDENTITY, QUAD_HALF, ALL_ROUND);
    try std.testing.expectEqual(RayIntersect.BoxFace.NegZ, back.Face.?);
    try ExpectVec3(.{ .x = 0, .y = 0, .z = -1 }, back.Normal);
}

test "RayRoundedBox2D rounds far more than the thickness" {
    //a 0.25 radius on a 0.002 thick plate, which RayRoundedBox can't do
    const corner = MakeRay(.{ .x = 0.95, .y = 0.95, .z = 5 }, .{ .x = 0, .y = 0, .z = -1 });
    try std.testing.expect(RayIntersect.RayBox(corner, ORIGIN, IDENTITY, QUAD_HALF).IsHit());
    try std.testing.expect(!RayIntersect.RayRoundedBox2D(corner, ORIGIN, IDENTITY, QUAD_HALF, ALL_ROUND).IsHit());
    //just inside the arc still hits
    try std.testing.expect(RayIntersect.RayRoundedBox2D(MakeRay(.{ .x = 0.9, .y = 0.9, .z = 5 }, .{ .x = 0, .y = 0, .z = -1 }), ORIGIN, IDENTITY, QUAD_HALF, ALL_ROUND).IsHit());
}

test "RayRoundedBox2D rounds each corner on its own" {
    //only the bottom left is rounded
    const radii = Vec4(f32){ .x = 0, .y = 0, .z = 0, .w = 0.25 };
    const dir = Vec3(f32){ .x = 0, .y = 0, .z = -1 };
    try std.testing.expect(!RayIntersect.RayRoundedBox2D(MakeRay(.{ .x = -0.95, .y = -0.95, .z = 5 }, dir), ORIGIN, IDENTITY, QUAD_HALF, radii).IsHit());
    try std.testing.expect(RayIntersect.RayRoundedBox2D(MakeRay(.{ .x = 0.95, .y = 0.95, .z = 5 }, dir), ORIGIN, IDENTITY, QUAD_HALF, radii).IsHit());
    try std.testing.expect(RayIntersect.RayRoundedBox2D(MakeRay(.{ .x = 0.95, .y = -0.95, .z = 5 }, dir), ORIGIN, IDENTITY, QUAD_HALF, radii).IsHit());
    try std.testing.expect(RayIntersect.RayRoundedBox2D(MakeRay(.{ .x = -0.95, .y = 0.95, .z = 5 }, dir), ORIGIN, IDENTITY, QUAD_HALF, radii).IsHit());
}

test "RayRoundedBox2D edge on hits the rounded side" {
    const s2 = @sqrt(@as(f32, 2));
    const hit = RayIntersect.RayRoundedBox2D(MakeRay(.{ .x = 5, .y = 5, .z = 0 }, .{ .x = -1, .y = -1, .z = 0 }), ORIGIN, IDENTITY, QUAD_HALF, ALL_ROUND);
    //the corner's arc is centered on (0.75, 0.75)
    try std.testing.expectApproxEqAbs(5 * s2 - (0.75 * s2 + 0.25), hit.T, eps);
    try std.testing.expectApproxEqAbs(5 * s2 + (0.75 * s2 + 0.25), hit.TExit, eps);
    try ExpectVec3(.{ .x = 1 / s2, .y = 1 / s2, .z = 0 }, hit.Normal);
    try std.testing.expect(hit.Face == null);
}

test "RayRoundedBox2D straight along z" {
    //no 2D movement at all, so it's inside the shape the whole way or never
    const inside = RayIntersect.RayRoundedBox2D(.{ .Origin = .{ .x = 0.5, .y = 0, .z = 5 }, .Dir = .{ .x = 0, .y = -0.0, .z = -1 } }, ORIGIN, IDENTITY, QUAD_HALF, ALL_ROUND);
    try std.testing.expect(inside.IsHit());
    try ExpectNoNaN(inside);
    const cut_off = RayIntersect.RayRoundedBox2D(.{ .Origin = .{ .x = 0.95, .y = 0.95, .z = 5 }, .Dir = .{ .x = -0.0, .y = 0, .z = -1 } }, ORIGIN, IDENTITY, QUAD_HALF, ALL_ROUND);
    try std.testing.expect(!cut_off.IsHit());
}

test "RayRoundedBox2D starting inside hits at zero" {
    const hit = RayIntersect.RayRoundedBox2D(MakeRay(.{ .x = 0, .y = 0, .z = 0 }, .{ .x = 0, .y = 0, .z = 1 }), ORIGIN, IDENTITY, .{ .x = 1, .y = 1, .z = 0.5 }, ALL_ROUND);
    try std.testing.expect(hit.StartedInside);
    try std.testing.expectEqual(@as(f32, 0), hit.T);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), hit.TExit, eps);
}

test "RayRoundedBox2D with no rounding is RayBox" {
    const ray = MakeRay(.{ .x = 0.3, .y = -0.6, .z = 5 }, .{ .x = 0.1, .y = 0.05, .z = -1 });
    const rotation = Quat(f32).FromAxisAngle((Vec3(f32){ .x = 1, .y = 2, .z = 0.5 }).Dir(), 0.4);
    const plain = RayIntersect.RayBox(ray, ORIGIN, rotation, QUAD_HALF);
    const rounded = RayIntersect.RayRoundedBox2D(ray, ORIGIN, rotation, QUAD_HALF, .{ .x = 0, .y = 0, .z = 0, .w = 0 });
    try std.testing.expectApproxEqAbs(plain.T, rounded.T, eps);
    try std.testing.expectApproxEqAbs(plain.TExit, rounded.TExit, eps);
    try ExpectVec3(plain.Normal, rounded.Normal);
    try std.testing.expectEqual(plain.Face.?, rounded.Face.?);
    try std.testing.expectApproxEqAbs(plain.UV.x, rounded.UV.x, eps);
    try std.testing.expectApproxEqAbs(plain.UV.y, rounded.UV.y, eps);
}

fn MarchRoundedBox2D(origin: Vec3(f32), dir: Vec3(f32), half: Vec3(f32), radii: Vec4(f32)) f32 {
    var t: f32 = 0;
    for (0..4000) |_| {
        const d = sdRoundedBox2DExtruded(origin.AddVec(dir.MulScalar(t)), half, radii);
        if (d < 0.00001) return t;
        t += d;
        if (t > 100) break;
    }
    return std.math.inf(f32);
}

test "RayRoundedBox2D agrees with sphere tracing" {
    var prng = std.Random.DefaultPrng.init(0x2D0B0C5E);
    const random = prng.random();

    var hits: usize = 0;
    var side_hits: usize = 0;
    var gap_starts: usize = 0;
    for (0..2000) |n| {
        const half = Vec3(f32){
            .x = 0.2 + random.float(f32) * 2,
            .y = 0.2 + random.float(f32) * 2,
            //thin plates and thick slabs both
            .z = if (n % 3 == 0) THICKNESS_2D else 0.05 + random.float(f32),
        };
        const max_r = @min(half.x, half.y);
        const radii = Vec4(f32){ .x = random.float(f32) * max_r, .y = random.float(f32) * max_r, .z = random.float(f32) * max_r, .w = random.float(f32) * max_r };

        const origin = if (n % 2 == 0) blk: {
            const offset = Vec3(f32){ .x = random.float(f32) - 0.5, .y = random.float(f32) - 0.5, .z = random.float(f32) - 0.5 };
            break :blk offset.Dir().MulScalar(8);
        } else Vec3(f32){
            .x = (random.float(f32) * 2 - 1) * half.x,
            .y = (random.float(f32) * 2 - 1) * half.y,
            .z = (random.float(f32) * 2 - 1) * half.z,
        };
        if (sdRoundedBox2DExtruded(origin, half, radii) <= 0.001) continue;
        if (n % 2 == 1) gap_starts += 1;

        const target = Vec3(f32){ .x = random.float(f32) * 3 - 1.5, .y = random.float(f32) * 3 - 1.5, .z = (random.float(f32) * 2 - 1) * half.z };
        const ray = MakeRay(origin, target.SubVec(origin));

        const hit = RayIntersect.RayRoundedBox2D(ray, ORIGIN, IDENTITY, half, radii);
        const marched = MarchRoundedBox2D(ray.Origin, ray.Dir, half, radii);

        if (!hit.IsHit()) {
            if (marched != std.math.inf(f32)) {
                try std.testing.expect(sdRoundedBox2DExtruded(ray.Origin.AddVec(ray.Dir.MulScalar(marched + 0.0005)), half, radii) > -0.0001);
            }
            continue;
        }
        hits += 1;
        if (hit.Face == null) side_hits += 1;
        try ExpectNoNaN(hit);

        const point = ray.Origin.AddVec(ray.Dir.MulScalar(hit.T));
        const exit_point = ray.Origin.AddVec(ray.Dir.MulScalar(hit.TExit));
        try std.testing.expectApproxEqAbs(@as(f32, 0), sdRoundedBox2DExtruded(point, half, radii), 0.001);
        try std.testing.expectApproxEqAbs(@as(f32, 0), sdRoundedBox2DExtruded(exit_point, half, radii), 0.001);
        try std.testing.expect(hit.TExit >= hit.T);
        try std.testing.expectApproxEqAbs(@as(f32, 1), hit.Normal.Len(), eps);
        try std.testing.expect(hit.Normal.Dot(ray.Dir) <= 0.0001);

        if (marched == std.math.inf(f32)) {
            const middle = ray.Origin.AddVec(ray.Dir.MulScalar((hit.T + hit.TExit) / 2));
            try std.testing.expect(sdRoundedBox2DExtruded(middle, half, radii) > -0.001);
        } else if (-hit.Normal.Dot(ray.Dir) > 0.1) {
            try std.testing.expectApproxEqAbs(marched, hit.T, 0.001);
        } else {
            try std.testing.expect(marched <= hit.T + 0.001);
        }
    }
    try std.testing.expect(hits > 300);
    try std.testing.expect(side_hits > 50);
    try std.testing.expect(gap_starts > 20);
}

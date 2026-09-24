const std = @import("std");
const MathTypes = @import("MathTypes.zig");
const RayIntersect = @import("RayIntersect.zig");
const Ray = @import("CameraRay.zig").Ray;
const Vec3 = MathTypes.Vec3;
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

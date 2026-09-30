const std = @import("std");
const MathTypes = @import("../../Math/MathTypes.zig");
const SDFFunc = @import("../../Math/SDFFunctions.zig");
const RayIntersect = @import("../../Math/RayIntersect.zig");
const Ray = @import("../../Math/CameraRay.zig").Ray;
const QuadData = @import("../../Renderer/Renderer2D.zig").QuadData;
const GlyphData = @import("../../Renderer/Renderer2D.zig").GlyphData;
const Vec2 = MathTypes.Vec2;
const Vec3 = MathTypes.Vec3;
const Vec4 = MathTypes.Vec4;
const Quat = MathTypes.Quat;

const eps: f32 = 0.0001;

const IDENTITY = Quat(f32){ .w = 1, .x = 0, .y = 0, .z = 0 };

fn MakeQuad(center: Vec3(f32), rotation: Quat(f32), half: Vec3(f32)) QuadData {
    return MakeRoundedQuad(center, rotation, half, .{ .x = 0, .y = 0, .z = 0, .w = 0 }, 0);
}

fn MakeRoundedQuad(center: Vec3(f32), rotation: Quat(f32), half: Vec3(f32), radii: Vec4(f32), border_width: f32) QuadData {
    return .{
        .Rotation = rotation.ToArray(),
        .Position = center.ToArray(),
        .HalfExtents = half.ToArray(),
        .ShadingHandle = 0,
        .ShadingFlags = 0,
        .BorderShadingHandle = 0,
        .BorderWidth = border_width,
        .CornerRadii = radii.ToArray(),
    };
}

fn ExpectVec3(expected: Vec3(f32), actual: Vec3(f32)) !void {
    try std.testing.expectApproxEqAbs(expected.x, actual.x, eps);
    try std.testing.expectApproxEqAbs(expected.y, actual.y, eps);
    try std.testing.expectApproxEqAbs(expected.z, actual.z, eps);
}

//gradBox, through normalRoundedBox with no rounding

test "gradBox on each face points out of that face" {
    const half = Vec3(f32){ .x = 1, .y = 2, .z = 3 };
    try ExpectVec3(.{ .x = 1, .y = 0, .z = 0 }, SDFFunc.normalRoundedBox(.{ .x = 1, .y = 0.5, .z = 0.5 }, half, 0));
    try ExpectVec3(.{ .x = -1, .y = 0, .z = 0 }, SDFFunc.normalRoundedBox(.{ .x = -1, .y = 0.5, .z = 0.5 }, half, 0));
    try ExpectVec3(.{ .x = 0, .y = -1, .z = 0 }, SDFFunc.normalRoundedBox(.{ .x = 0.5, .y = -2, .z = 0.5 }, half, 0));
    try ExpectVec3(.{ .x = 0, .y = 0, .z = 1 }, SDFFunc.normalRoundedBox(.{ .x = 0.5, .y = 0.5, .z = 3 }, half, 0));
}

test "gradBox just outside and just inside a face agree" {
    const half = Vec3(f32){ .x = 1, .y = 1, .z = 0.001 };
    try ExpectVec3(.{ .x = 0, .y = 0, .z = 1 }, SDFFunc.normalRoundedBox(.{ .x = 0.3, .y = -0.4, .z = 0.0015 }, half, 0));
    try ExpectVec3(.{ .x = 0, .y = 0, .z = 1 }, SDFFunc.normalRoundedBox(.{ .x = 0.3, .y = -0.4, .z = 0.0005 }, half, 0));
}

test "gradBox past an edge blends the two faces" {
    const d = std.math.sqrt1_2;
    try ExpectVec3(.{ .x = d, .y = d, .z = 0 }, SDFFunc.normalRoundedBox(.{ .x = 1.1, .y = 1.1, .z = 0 }, .{ .x = 1, .y = 1, .z = 1 }, 0));
}

//==================================rayIM==================================

fn MakeGlyph(position: Vec3(f32), rotation: Quat(f32), half: Vec3(f32), plane_center: Vec2(f32)) GlyphData {
    return .{
        .Rotation = rotation.ToArray(),
        .Position = position.ToArray(),
        .HalfExtents = half.ToArray(),
        .PlaneCenter = plane_center.ToArray(),
        .AtlasShadingHandle = 0,
        .TextureShadingFlags = 0,
    };
}

test "rayIMQuad front and back" {
    const quad = MakeQuad(.{ .x = 1, .y = 2, .z = 3 }, IDENTITY, .{ .x = 1, .y = 1, .z = SDFFunc.THICKNESS_2D });

    const front = SDFFunc.rayIMQuad(.{ .Origin = .{ .x = 1.5, .y = 2.5, .z = 10 }, .Dir = .{ .x = 0, .y = 0, .z = -1 } }, quad);
    try std.testing.expectEqual(RayIntersect.BoxFace.PosZ, front.Face.?);
    try std.testing.expectApproxEqAbs(@as(f32, 7 - SDFFunc.THICKNESS_2D), front.T, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), front.UV.x, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), front.UV.y, eps);

    //the marcher turns this one down, only fronts are drawn
    const back = SDFFunc.rayIMQuad(.{ .Origin = .{ .x = 1.5, .y = 2.5, .z = -10 }, .Dir = .{ .x = 0, .y = 0, .z = 1 } }, quad);
    try std.testing.expectEqual(RayIntersect.BoxFace.NegZ, back.Face.?);
}

test "rayIMGlyph box sits PlaneCenter off the glyph in its own plane" {
    //a quarter turn about z sends the glyph's +x along world +y, so the box is at (2, 0.5, 0)
    const rotation = Quat(f32).FromAxisAngle(.{ .x = 0, .y = 0, .z = 1 }, std.math.pi / 2.0);
    const glyph = MakeGlyph(.{ .x = 2, .y = 0, .z = 0 }, rotation, .{ .x = 0.25, .y = 0.5, .z = SDFFunc.THICKNESS_2D }, .{ .x = 0.5, .y = 0 });

    const center = SDFFunc.rayIMGlyph(.{ .Origin = .{ .x = 2, .y = 0.5, .z = 5 }, .Dir = .{ .x = 0, .y = 0, .z = -1 } }, glyph);
    try std.testing.expectEqual(RayIntersect.BoxFace.PosZ, center.Face.?);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), center.UV.x, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), center.UV.y, eps);
    try ExpectVec3(.{ .x = 0, .y = 0, .z = 1 }, center.Normal);

    //the glyph's own position is off its box
    try std.testing.expect(!SDFFunc.rayIMGlyph(.{ .Origin = .{ .x = 2, .y = -0.1, .z = 5 }, .Dir = .{ .x = 0, .y = 0, .z = -1 } }, glyph).IsHit());

    //and the box agrees with the distance the march uses
    const point = Vec3(f32){ .x = 2, .y = 0.5, .z = 5 - center.T };
    try std.testing.expectApproxEqAbs(@as(f32, 0), SDFFunc.sdIMGlyph(point, glyph), eps);
}

test "opRound pushes the surface out by the radius" {
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), SDFFunc.opRound(1.0, 0.25), eps);
    try std.testing.expectApproxEqAbs(@as(f32, -0.25), SDFFunc.opRound(0.0, 0.25), eps);
}

test "sdRoundedBox keeps the flat faces where the plain box has them" {
    const half = Vec3(f32){ .x = 1, .y = 1, .z = 1 };
    try std.testing.expectApproxEqAbs(@as(f32, 0), SDFFunc.sdRoundedBox(.{ .x = 0, .y = 0, .z = 1 }, half, 0.25), eps);
    //a plain box's corner is cut away, by sqrt(3) * 0.25 - 0.25 along the diagonal
    try std.testing.expectApproxEqAbs(@sqrt(@as(f32, 3)) * 0.25 - 0.25, SDFFunc.sdRoundedBox(.{ .x = 1, .y = 1, .z = 1 }, half, 0.25), eps);
}

test "sdRoundedBox and normalRoundedBox agree with RayRoundedBox" {
    var prng = std.Random.DefaultPrng.init(0x0B0C5D0F);
    const random = prng.random();

    var hits: usize = 0;
    for (0..500) |_| {
        const half = Vec3(f32){ .x = 0.2 + random.float(f32) * 2, .y = 0.2 + random.float(f32) * 2, .z = 0.2 + random.float(f32) * 2 };
        const radius = random.float(f32) * @min(half.x, @min(half.y, half.z));

        const offset = Vec3(f32){ .x = random.float(f32) - 0.5, .y = random.float(f32) - 0.5, .z = random.float(f32) - 0.5 };
        const origin = offset.Dir().MulScalar(8);
        const target = Vec3(f32){ .x = random.float(f32) * 3 - 1.5, .y = random.float(f32) * 3 - 1.5, .z = random.float(f32) * 3 - 1.5 };
        const ray = Ray{ .Origin = origin, .Dir = target.SubVec(origin).Dir() };

        const hit = RayIntersect.RayRoundedBox(ray, .{ .x = 0, .y = 0, .z = 0 }, IDENTITY, half, radius);
        if (!hit.IsHit()) continue;
        hits += 1;

        const point = ray.Origin.AddVec(ray.Dir.MulScalar(hit.T));
        try std.testing.expectApproxEqAbs(@as(f32, 0), SDFFunc.sdRoundedBox(point, half, radius), 0.001);
        try std.testing.expectApproxEqAbs(@as(f32, 1), SDFFunc.normalRoundedBox(point, half, radius).Dot(hit.Normal), 0.001);
    }
    try std.testing.expect(hits > 100);
}

test "sdRoundedBox2D rounds each corner by its own radius" {
    const half = Vec2(f32){ .x = 1, .y = 1 };
    //only the top right is rounded, iq's radii.x
    const radii = Vec4(f32){ .x = 0.5, .y = 0, .z = 0, .w = 0 };
    const cut = @sqrt(@as(f32, 2)) * 0.5 - 0.5;
    try std.testing.expectApproxEqAbs(cut, SDFFunc.sdRoundedBox2D(.{ .x = 1, .y = 1 }, half, radii), eps);
    try std.testing.expectApproxEqAbs(@as(f32, 0), SDFFunc.sdRoundedBox2D(.{ .x = -1, .y = 1 }, half, radii), eps);
    try std.testing.expectApproxEqAbs(@as(f32, 0), SDFFunc.sdRoundedBox2D(.{ .x = 1, .y = -1 }, half, radii), eps);
    try std.testing.expectApproxEqAbs(@as(f32, 0), SDFFunc.sdRoundedBox2D(.{ .x = -1, .y = -1 }, half, radii), eps);
}

test "opExtrusion keeps the 2D shape and adds the thickness" {
    const half = Vec2(f32){ .x = 1, .y = 1 };
    const radii = Vec4(f32){ .x = 0.25, .y = 0.25, .z = 0.25, .w = 0.25 };
    const front = Vec3(f32){ .x = 0.2, .y = 0.3, .z = 0.1 };
    try std.testing.expectApproxEqAbs(@as(f32, 0), SDFFunc.opExtrusion(front, SDFFunc.sdRoundedBox2D(.{ .x = front.x, .y = front.y }, half, radii), 0.1), eps);
    //straight out past the rounded side, level with the slab, is only the 2D distance
    const side = Vec3(f32){ .x = 1.5, .y = 0, .z = 0.05 };
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), SDFFunc.opExtrusion(side, SDFFunc.sdRoundedBox2D(.{ .x = side.x, .y = side.y }, half, radii), 0.1), eps);
}

test "opExtrusion of sdRoundedBox2D and normalExtrusion agree with RayRoundedBox2D" {
    var prng = std.Random.DefaultPrng.init(0x0E0B2D0F);
    const random = prng.random();

    var hits: usize = 0;
    for (0..1000) |n| {
        const half = Vec3(f32){ .x = 0.2 + random.float(f32) * 2, .y = 0.2 + random.float(f32) * 2, .z = if (n % 3 == 0) SDFFunc.THICKNESS_2D else 0.05 + random.float(f32) };
        const max_r = @min(half.x, half.y);
        const radii = Vec4(f32){ .x = random.float(f32) * max_r, .y = random.float(f32) * max_r, .z = random.float(f32) * max_r, .w = random.float(f32) * max_r };

        const offset = Vec3(f32){ .x = random.float(f32) - 0.5, .y = random.float(f32) - 0.5, .z = random.float(f32) - 0.5 };
        const origin = offset.Dir().MulScalar(8);
        const target = Vec3(f32){ .x = random.float(f32) * 3 - 1.5, .y = random.float(f32) * 3 - 1.5, .z = (random.float(f32) * 2 - 1) * half.z };
        const ray = Ray{ .Origin = origin, .Dir = target.SubVec(origin).Dir() };

        const hit = RayIntersect.RayRoundedBox2D(ray, .{ .x = 0, .y = 0, .z = 0 }, IDENTITY, half, radii);
        if (!hit.IsHit()) continue;

        const point = ray.Origin.AddVec(ray.Dir.MulScalar(hit.T));
        const point_2d = Vec2(f32){ .x = point.x, .y = point.y };
        const half_2d = Vec2(f32){ .x = half.x, .y = half.y };
        const distance_2d = SDFFunc.sdRoundedBox2D(point_2d, half_2d, radii);
        try std.testing.expectApproxEqAbs(@as(f32, 0), SDFFunc.opExtrusion(point, distance_2d, half.z), 0.001);

        //where the side meets the front the two are an edge apart, and either normal is fair
        if (@abs(distance_2d) < 0.001 and @abs(@abs(point.z) - half.z) < 0.001) continue;
        hits += 1;

        const normal = SDFFunc.normalExtrusion(point, distance_2d, SDFFunc.normalRoundedBox2D(point_2d, half_2d, radii), half.z);
        try std.testing.expectApproxEqAbs(@as(f32, 1), normal.Dot(hit.Normal), 0.001);
    }
    try std.testing.expect(hits > 200);
}

//a quad as the marcher sees it: a rounded plate, and its border band

test "a quad with square corners is exactly the plain box, and rounding only cuts the corners" {
    const half = Vec3(f32){ .x = 2, .y = 1, .z = SDFFunc.THICKNESS_2D };
    const square = MakeQuad(.{ .x = 0, .y = 0, .z = 0 }, IDENTITY, half);
    const rounded = MakeRoundedQuad(.{ .x = 0, .y = 0, .z = 0 }, IDENTITY, half, .{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 0.5 }, 0);

    //in front of the middle, and off the right edge: rounding changes neither
    for ([_]Vec3(f32){ .{ .x = 0, .y = 0, .z = 3 }, .{ .x = 3, .y = 0, .z = 0 } }) |point| {
        try std.testing.expectApproxEqAbs(@as(f32, point.x + point.z - (if (point.x > 0) half.x else half.z)), SDFFunc.sdIMQuad(point, square), eps);
        try std.testing.expectApproxEqAbs(SDFFunc.sdIMQuad(point, square), SDFFunc.sdIMQuad(point, rounded), eps);
    }

    //just inside the square corner is on the square quad, but outside the rounded one
    const corner = Vec3(f32){ .x = 1.95, .y = 0.95, .z = 0 };
    try std.testing.expect(SDFFunc.sdIMQuad(corner, square) <= 0);
    try std.testing.expect(SDFFunc.sdIMQuad(corner, rounded) > 0);
}

test "the border band runs along the edge, round the rounded corners, and only as wide as the border" {
    const half = Vec3(f32){ .x = 2, .y = 1, .z = SDFFunc.THICKNESS_2D };
    const quad = MakeRoundedQuad(.{ .x = 0, .y = 0, .z = 0 }, IDENTITY, half, .{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 0.5 }, 0.1);

    try std.testing.expect(SDFFunc.InIMQuadBorder(.{ .x = 1.95, .y = 0, .z = 0 }, quad));
    try std.testing.expect(!SDFFunc.InIMQuadBorder(.{ .x = 1.85, .y = 0, .z = 0 }, quad));
    try std.testing.expect(!SDFFunc.InIMQuadBorder(.{ .x = 0, .y = 0, .z = 0 }, quad));
    //on the curve of the top right corner, whose center is (1.5, 0.5), 0.05 in from it
    const along_curve = Vec3(f32){ .x = 1.5 + 0.45 * 0.7071, .y = 0.5 + 0.45 * 0.7071, .z = 0 };
    try std.testing.expect(SDFFunc.InIMQuadBorder(along_curve, quad));

    //no border: nothing is in it
    const plain = MakeRoundedQuad(.{ .x = 0, .y = 0, .z = 0 }, IDENTITY, half, .{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 0.5 }, 0);
    try std.testing.expect(!SDFFunc.InIMQuadBorder(.{ .x = 1.99, .y = 0, .z = 0 }, plain));
}

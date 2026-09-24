const std = @import("std");
const MathTypes = @import("MathTypes.zig");
const CameraRay = @import("CameraRay.zig");
const Vec2 = MathTypes.Vec2;
const Vec3 = MathTypes.Vec3;
const Quat = MathTypes.Quat;

const eps: f32 = 0.0001;

const FOV: f32 = std.math.degreesToRadians(60.0);
const WIDTH: f32 = 1600.0;
const HEIGHT: f32 = 900.0;

const FORWARD = Vec3(f32){ .x = 0, .y = 0, .z = -1 };
const IDENTITY = Quat(f32){ .w = 1, .x = 0, .y = 0, .z = 0 };

fn ExpectVec3(expected: Vec3(f32), actual: Vec3(f32)) !void {
    try std.testing.expectApproxEqAbs(expected.x, actual.x, eps);
    try std.testing.expectApproxEqAbs(expected.y, actual.y, eps);
    try std.testing.expectApproxEqAbs(expected.z, actual.z, eps);
}

fn AngleBetween(a: Vec3(f32), b: Vec3(f32)) f32 {
    return std.math.acos(std.math.clamp(a.Dot(b), -1.0, 1.0));
}

test "center pixel looks straight down -Z" {
    const params = CameraRay.ComputeRayParams(FOV, WIDTH, HEIGHT);
    const dir = CameraRay.PixelToViewDir(params, .{ .x = WIDTH / 2, .y = HEIGHT / 2 });
    try ExpectVec3(FORWARD, dir);
}

test "top edge is half the fov above forward" {
    const params = CameraRay.ComputeRayParams(FOV, WIDTH, HEIGHT);
    const dir = CameraRay.PixelToViewDir(params, .{ .x = WIDTH / 2, .y = 0 });
    //pixels are y-down, the view is y-up
    try std.testing.expect(dir.y > 0);
    try std.testing.expectApproxEqAbs(FOV / 2, AngleBetween(dir, FORWARD), eps);
}

test "left edge is the horizontal half fov to the left of forward" {
    const params = CameraRay.ComputeRayParams(FOV, WIDTH, HEIGHT);
    const dir = CameraRay.PixelToViewDir(params, .{ .x = 0, .y = HEIGHT / 2 });
    const half_hfov = std.math.atan(@tan(FOV / 2) * WIDTH / HEIGHT);
    try std.testing.expect(dir.x < 0);
    try std.testing.expectApproxEqAbs(half_hfov, AngleBetween(dir, FORWARD), eps);
}

test "opposite corners mirror each other" {
    const params = CameraRay.ComputeRayParams(FOV, WIDTH, HEIGHT);
    const top_left = CameraRay.PixelToViewDir(params, .{ .x = 0, .y = 0 });
    const bottom_right = CameraRay.PixelToViewDir(params, .{ .x = WIDTH, .y = HEIGHT });
    try ExpectVec3(.{ .x = -bottom_right.x, .y = -bottom_right.y, .z = bottom_right.z }, top_left);
}

test "pixels are square in landscape and portrait" {
    const sizes = [_][2]f32{ .{ 1920, 1080 }, .{ 1080, 1920 }, .{ 1, 1 } };
    for (sizes) |size| {
        const params = CameraRay.ComputeRayParams(FOV, size[0], size[1]);
        try std.testing.expectApproxEqAbs(@abs(params.Scale.x), @abs(params.Scale.y), eps);
    }
}

test "pixel coordinates are continuous" {
    const params = CameraRay.ComputeRayParams(FOV, WIDTH, HEIGHT);
    //compare view plane points (before normalizing), where the mapping is exactly linear
    const a = params.Scale.MulVec(.{ .x = 10, .y = 20 }).AddVec(params.Offset);
    const b = params.Scale.MulVec(.{ .x = 11, .y = 21 }).AddVec(params.Offset);
    const mid = params.Scale.MulVec(.{ .x = 10.5, .y = 20.5 }).AddVec(params.Offset);
    try std.testing.expectApproxEqAbs((a.x + b.x) / 2, mid.x, eps);
    try std.testing.expectApproxEqAbs((a.y + b.y) / 2, mid.y, eps);
}

test "MakeRay with an identity pose is the view direction from the camera position" {
    const params = CameraRay.ComputeRayParams(FOV, WIDTH, HEIGHT);
    const position = Vec3(f32){ .x = 1, .y = 2, .z = 15 };
    const pixel = Vec2(f32){ .x = 123.25, .y = 456.75 };
    const ray = CameraRay.MakeRay(.{ .Position = position, .Rotation = IDENTITY }, params, pixel);
    try ExpectVec3(position, ray.Origin);
    try ExpectVec3(CameraRay.PixelToViewDir(params, pixel), ray.Dir);
}

test "MakeRay follows the camera rotation" {
    const params = CameraRay.ComputeRayParams(FOV, WIDTH, HEIGHT);
    //yaw 90 degrees left about +Y: forward (-Z) turns to -X
    const yaw = Quat(f32).FromAxisAngle(.{ .x = 0, .y = 1, .z = 0 }, std.math.degreesToRadians(90.0));
    const ray = CameraRay.MakeRay(.{ .Position = .{ .x = 0, .y = 0, .z = 0 }, .Rotation = yaw }, params, .{ .x = WIDTH / 2, .y = HEIGHT / 2 });
    try ExpectVec3(.{ .x = -1, .y = 0, .z = 0 }, ray.Dir);
}

test "ray directions are normalized" {
    const params = CameraRay.ComputeRayParams(FOV, WIDTH, HEIGHT);
    const pixels = [_]Vec2(f32){ .{ .x = 0, .y = 0 }, .{ .x = WIDTH, .y = 0 }, .{ .x = 37.5, .y = 800 } };
    for (pixels) |pixel| {
        try std.testing.expectApproxEqAbs(@as(f32, 1.0), CameraRay.PixelToViewDir(params, pixel).Len(), eps);
    }
}

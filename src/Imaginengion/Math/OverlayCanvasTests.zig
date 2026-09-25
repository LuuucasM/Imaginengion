const std = @import("std");
const MathTypes = @import("MathTypes.zig");
const CameraRay = @import("CameraRay.zig");
const OverlayCanvas = @import("OverlayCanvas.zig");
const Vec2 = MathTypes.Vec2;
const Vec3 = MathTypes.Vec3;
const Quat = MathTypes.Quat;

//canvas units come back from a ray/plane intersection, so a little looser than exact math
const eps: f32 = 0.001;

const IDENTITY = Quat(f32){ .w = 1, .x = 0, .y = 0, .z = 0 };
const ORIGIN_POSE = CameraRay.Pose{ .Position = .{ .x = 0, .y = 0, .z = 0 }, .Rotation = IDENTITY };

/// A camera somewhere odd: moved and turned on two axes, so nothing lines up by accident.
fn OddPose() CameraRay.Pose {
    const yaw = Quat(f32).FromAxisAngle(.{ .x = 0, .y = 1, .z = 0 }, std.math.degreesToRadians(35.0));
    const pitch = Quat(f32).FromAxisAngle(.{ .x = 1, .y = 0, .z = 0 }, std.math.degreesToRadians(-20.0));
    return .{ .Position = .{ .x = 12, .y = -4, .z = 30 }, .Rotation = yaw.MulQuat(pitch) };
}

/// Where the shaders' ray through `pixel` lands on the canvas, in canvas units. This is the same ray
/// the overlay pass traces, so it checks the canvas math against what will actually be drawn.
fn CanvasPointAtPixel(pose: CameraRay.Pose, fov_rad: f32, width: f32, height: f32, pixels_per_unit: f32, pixel: Vec2(f32)) Vec3(f32) {
    const canvas = OverlayCanvas.ComputeCanvasTransform(pose, @tan(fov_rad / 2), height, pixels_per_unit);
    const ray = CameraRay.MakeRay(pose, CameraRay.ComputeRayParams(fov_rad, width, height), pixel);
    //a ray through any pixel of the camera looking at the canvas crosses it
    return canvas.RayToCanvasPoint(ray).?;
}

fn ExpectCanvas(expected_x: f32, expected_y: f32, actual: Vec3(f32)) !void {
    try std.testing.expectApproxEqAbs(expected_x, actual.x, eps);
    try std.testing.expectApproxEqAbs(expected_y, actual.y, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 0), actual.z, eps);
}

test "pixels per unit for each mode" {
    //constant pixel size only follows the OS display scale
    try std.testing.expectEqual(@as(f32, 1.5), OverlayCanvas.PixelsPerUnit(.ConstantPixelSize, 1080, 1.5));
    try std.testing.expectEqual(@as(f32, 1.5), OverlayCanvas.PixelsPerUnit(.ConstantPixelSize, 2160, 1.5));
    //scale with screen follows the target's height against the reference
    try std.testing.expectEqual(@as(f32, 1), OverlayCanvas.PixelsPerUnit(.ScaleWithScreen, 1080, 1.5));
    try std.testing.expectEqual(@as(f32, 2), OverlayCanvas.PixelsPerUnit(.ScaleWithScreen, 2160, 1.5));
}

test "the screen center is the canvas origin" {
    const fov = std.math.degreesToRadians(60.0);
    try ExpectCanvas(0, 0, CanvasPointAtPixel(ORIGIN_POSE, fov, 1600, 900, 1, .{ .x = 800, .y = 450 }));
}

test "one canvas unit covers pixels_per_unit pixels, x right and y up" {
    const fov = std.math.degreesToRadians(60.0);
    const k: f32 = 1.5;
    //100 units right and 50 up from center is 150 px right and 75 px up (pixel y runs down)
    const pixel = Vec2(f32){ .x = 800 + 100 * k, .y = 450 - 50 * k };
    try ExpectCanvas(100, 50, CanvasPointAtPixel(ORIGIN_POSE, fov, 1600, 900, k, pixel));
}

test "scale with screen covers the same share of any screen" {
    const fov = std.math.degreesToRadians(60.0);
    //the top edge is always half the reference height up, whatever the real height
    for ([_]f32{ 720, 1080, 2160 }) |height| {
        const k = OverlayCanvas.PixelsPerUnit(.ScaleWithScreen, height, 1);
        const top_center = CanvasPointAtPixel(ORIGIN_POSE, fov, height * 16 / 9, height, k, .{ .x = height * 8 / 9, .y = 0 });
        try ExpectCanvas(0, OverlayCanvas.REFERENCE_HEIGHT / 2, top_center);
    }
}

test "constant pixel size shows more canvas on a bigger screen" {
    const fov = std.math.degreesToRadians(60.0);
    //the top edge is half the pixel height up, so the canvas visible grows with the screen
    for ([_]f32{ 720, 1080, 2160 }) |height| {
        const top_center = CanvasPointAtPixel(ORIGIN_POSE, fov, height * 16 / 9, height, 1, .{ .x = height * 8 / 9, .y = 0 });
        try ExpectCanvas(0, height / 2, top_center);
    }
}

test "zooming the fov doesn't move canvas content" {
    const pixel = Vec2(f32){ .x = 800 + 200, .y = 450 + 120 };
    for ([_]f32{ 20, 60, 100 }) |fov_degrees| {
        const fov = std.math.degreesToRadians(fov_degrees);
        try ExpectCanvas(200, -120, CanvasPointAtPixel(ORIGIN_POSE, fov, 1600, 900, 1, pixel));
    }
}

test "moving and turning the camera doesn't move canvas content" {
    const fov = std.math.degreesToRadians(60.0);
    const pixel = Vec2(f32){ .x = 800 - 300, .y = 450 - 200 };
    try ExpectCanvas(-300, 200, CanvasPointAtPixel(OddPose(), fov, 1600, 900, 1, pixel));
}

test "wide and tall targets keep square pixels" {
    const fov = std.math.degreesToRadians(60.0);
    //the same 100 px step right lands on 100 units whatever the aspect ratio
    try ExpectCanvas(100, 0, CanvasPointAtPixel(ORIGIN_POSE, fov, 2560, 1080, 1, .{ .x = 1280 + 100, .y = 540 }));
    try ExpectCanvas(100, 0, CanvasPointAtPixel(ORIGIN_POSE, fov, 1080, 1920, 1, .{ .x = 540 + 100, .y = 960 }));
}

test "the canvas sits CANVAS_DISTANCE in front of the camera" {
    const pose = OddPose();
    const canvas = OverlayCanvas.ComputeCanvasTransform(pose, @tan(std.math.degreesToRadians(@as(f32, 60.0)) / 2), 900, 1);
    const forward = (Vec3(f32){ .x = 0, .y = 0, .z = -1 }).QuatRotate(pose.Rotation);
    const to_canvas = canvas.Position.SubVec(pose.Position);
    try std.testing.expectApproxEqAbs(OverlayCanvas.CANVAS_DISTANCE, to_canvas.Len(), eps);
    try std.testing.expectApproxEqAbs(@as(f32, 1), to_canvas.Dir().Dot(forward), 0.0001);
}

test "a ray that can't reach the canvas plane has no canvas point" {
    const canvas = OverlayCanvas.ComputeCanvasTransform(ORIGIN_POSE, @tan(std.math.degreesToRadians(@as(f32, 60.0)) / 2), 900, 1);
    const origin = Vec3(f32){ .x = 0, .y = 0, .z = 0 };
    //pointing backwards, away from the canvas
    try std.testing.expect(canvas.RayToCanvasPoint(.{ .Origin = origin, .Dir = .{ .x = 0, .y = 0, .z = 1 } }) == null);
    //running sideways, along the plane
    try std.testing.expect(canvas.RayToCanvasPoint(.{ .Origin = origin, .Dir = .{ .x = 1, .y = 0, .z = 0 } }) == null);
}

test "canvas to world and back is the same point" {
    const canvas = OverlayCanvas.ComputeCanvasTransform(OddPose(), @tan(std.math.degreesToRadians(@as(f32, 45.0)) / 2), 1080, 2);
    const point = Vec3(f32){ .x = -250, .y = 130, .z = 40 };
    const back = canvas.ToCanvasPoint(canvas.ToWorldPoint(point));
    try std.testing.expectApproxEqAbs(point.x, back.x, eps);
    try std.testing.expectApproxEqAbs(point.y, back.y, eps);
    try std.testing.expectApproxEqAbs(point.z, back.z, eps);
}

test "a tilted canvas box keeps its shape in the world" {
    //uniform scale and a rotation: an edge of a rotated box scales by Scale and turns with the camera
    const pose = OddPose();
    const canvas = OverlayCanvas.ComputeCanvasTransform(pose, @tan(std.math.degreesToRadians(@as(f32, 60.0)) / 2), 900, 1);
    const box_rotation = Quat(f32).FromAxisAngle(.{ .x = 0, .y = 1, .z = 0 }, std.math.degreesToRadians(40.0));
    const edge = Vec3(f32){ .x = 80, .y = 0, .z = 0 };

    //the edge's world position difference, done point by point
    const center = Vec3(f32){ .x = 10, .y = 20, .z = 5 };
    const world_edge = canvas.ToWorldPoint(center.AddVec(edge.QuatRotate(box_rotation))).SubVec(canvas.ToWorldPoint(center));
    //the same edge through ToWorldRotation and ToWorldVector, the way the renderer will upload a box
    const via_transform = canvas.ToWorldVector(edge).QuatRotate(canvas.ToWorldRotation(box_rotation));

    try std.testing.expectApproxEqAbs(world_edge.x, via_transform.x, 0.00001);
    try std.testing.expectApproxEqAbs(world_edge.y, via_transform.y, 0.00001);
    try std.testing.expectApproxEqAbs(world_edge.z, via_transform.z, 0.00001);
    try std.testing.expectApproxEqAbs(edge.Len() * canvas.Scale, world_edge.Len(), 0.00001);
}

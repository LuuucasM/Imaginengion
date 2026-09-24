const MathTypes = @import("MathTypes.zig");
const Vec2 = MathTypes.Vec2;
const Vec3 = MathTypes.Vec3;
const Quat = MathTypes.Quat;

/// Maps a pixel coordinate to a point on the view plane at z = -1 (camera looks down -Z, +Y up).
pub const RayParams = struct {
    Scale: Vec2(f32),
    Offset: Vec2(f32),
};

pub const Pose = struct {
    Position: Vec3(f32),
    Rotation: Quat(f32),
};

pub const Ray = struct {
    Origin: Vec3(f32),
    Dir: Vec3(f32), // normalized
};

/// CPU only. Perspective params with square pixels; aspect comes from width/height directly.
pub fn ComputeRayParams(fov_rad: f32, width: f32, height: f32) RayParams {
    const t = @tan(fov_rad / 2);
    return .{
        .Scale = .{ .x = 2 * t / height, .y = -2 * t / height },
        .Offset = .{ .x = -t * width / height, .y = t },
    };
}

/// `pixel` is a continuous coordinate: pixel i covers [i, i+1), origin top-left, +y down.
/// Shaders pass `index + 0.5` (pixel center); the CPU passes the mouse position as-is.
pub fn PixelToViewDir(params: RayParams, pixel: Vec2(f32)) Vec3(f32) {
    const plane_point = params.Scale.MulVec(pixel).AddVec(params.Offset);
    return Vec3(f32).Dir(.{ .x = plane_point.x, .y = plane_point.y, .z = -1.0 });
}

pub fn MakeRay(pose: Pose, params: RayParams, pixel: Vec2(f32)) Ray {
    return .{
        .Origin = pose.Position,
        .Dir = PixelToViewDir(params, pixel).QuatRotate(pose.Rotation),
    };
}

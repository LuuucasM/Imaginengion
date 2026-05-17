const std = @import("std");
const math = std.math;

pub fn IsValidFloat(f: f32) bool {
    return !std.math.isNan(f) and !std.math.isInf(f);
}

pub fn DegreesToRadians(degrees: anytype) @TypeOf(degrees) {
    std.debug.assert(@typeInfo(@TypeOf(degrees)) == .float or
        @typeInfo(@TypeOf(degrees)) == .comptime_float);
    return degrees * math.pi / 180.0;
}

pub fn RadiansToDegrees(radians: anytype) @TypeOf(radians) {
    std.debug.assert(@typeInfo(@TypeOf(radians)) == .float or
        @typeInfo(@TypeOf(radians)) == .comptime_float);
    return radians * 180.0 / math.pi;
}

pub fn PerspectiveRHNO(fovy_radians: f32, aspect: f32, zNear: f32, zFar: f32) Mat4f32 {
    const tanHalfFovy = math.tan(fovy_radians / 2);
    return .{
        Vec4f32{ 1.0 / (aspect * tanHalfFovy), 0.0, 0.0, 0.0 },
        Vec4f32{ 0.0, -1 / tanHalfFovy, 0.0, 0.0 },
        Vec4f32{ 0.0, 0.0, -((zFar + zNear) / (zFar - zNear)), -1.0 },
        Vec4f32{ 0.0, 0.0, -((2.0 * zFar * zNear) / (zFar - zNear)), 0.0 },
    };
}

pub fn OrthographicRHNO(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) Mat4f32 {
    const width = right - left;
    const height = top - bottom;
    const depth = far - near;

    return Mat4f32{
        Vec4f32{ 2.0 / width, 0.0, 0.0, -(right + left) / width },
        Vec4f32{ 0.0, 2.0 / height, 0.0, -(top + bottom) / height },
        Vec4f32{ 0.0, 0.0, -2.0 / depth, -(far + near) / depth },
        Vec4f32{ 0.0, 0.0, 0.0, 1.0 },
    };
}

pub fn Translate(v: Vec3f32) Mat4f32 {
    const m = Mat4Identity();
    var result = m;
    result[3] = (m[0] * @as(Vec4f32, @splat(v[0]))) + (m[1] * @as(Vec4f32, @splat(v[1]))) + (m[2] * @as(Vec4f32, @splat(v[2]))) + m[3];
    return result;
}

pub fn Scale(v: Vec3f32) Mat4f32 {
    const m = Mat4Identity();
    return Mat4f32{
        m[0] * @as(Vec4f32, @splat(v[0])),
        m[1] * @as(Vec4f32, @splat(v[1])),
        m[2] * @as(Vec4f32, @splat(v[2])),
        m[3],
    };
}

pub fn QuatAngleAxis(angle_degrees: f32, axis: Vec3f32) Quatf32 {
    const rad_ang = DegreesToRadians(angle_degrees);
    const half_sin = math.sin(rad_ang * 0.5);
    return Quatf32{
        math.cos(half_sin),
        axis[0] * half_sin,
        axis[1] * half_sin,
        axis[2] * half_sin,
    };
}

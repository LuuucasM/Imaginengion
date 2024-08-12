const std = @import("std");
const math = std.math;
pub const Vec1f32 = @Vector(1, f32);
pub const Vec2f32 = @Vector(2, f32);
pub const Vec3f32 = @Vector(3, f32);
pub const Vec4f32 = @Vector(4, f32);
pub const Mat2f32 = [2]Vec2f32;
pub const Mat3f32 = [3]Vec3f32;
pub const Mat4f32 = [4]Vec4f32;
pub const Quatf32 = @Vector(4, f32);

pub fn InitMat4CompTime(x: comptime_float) Mat4f32 {
    return .{
        Vec4f32{ x, 0.0, 0.0, 0.0 },
        Vec4f32{ 0.0, x, 0.0, 0.0 },
        Vec4f32{ 0.0, 0.0, x, 0.0 },
        Vec4f32{ 0.0, 0.0, 0.0, x },
    };
}

fn Mat4MulVec(m: Vec4f32, v: Mat4f32) @TypeOf(m) {
    const mov0: @TypeOf(m) = @splat(m[0]);
    const mov1: @TypeOf(m) = @splat(m[1]);
    const mul0 = v[0] * mov0;
    const mul1 = v[1] * mov1;
    const add0 = mul0 + mul1;

    const mov2: @TypeOf(m) = @splat(m[2]);
    const mov3: @TypeOf(m) = @splat(m[3]);
    const mul2 = v[2] * mov2;
    const mul3 = v[3] * mov3;
    const add1 = mul2 + mul3;

    return add0 + add1;
}

pub fn Mat4Mul(m: Mat4f32, v: Mat4f32) Mat4f32 {
    return .{
        Mat4MulVec(m[0], v),
        Mat4MulVec(m[1], v),
        Mat4MulVec(m[2], v),
        Mat4MulVec(m[3], v),
    };
}

pub fn Radians(degrees: anytype) @TypeOf(degrees) {
    std.debug.assert(@typeInfo(degrees) == .Float);
    return degrees * math.pi / 180.0;
}

pub fn PerspectiveRHGL(fovy: f32, aspect: f32, zNear: f32, zFar: f32) Mat4f32 {
    const tanHalfFovy = math.tan(fovy / 2);
    return .{
        Vec4f32{ 1.0 / (aspect * tanHalfFovy), 0.0, 0.0, 0.0 },
        Vec4f32{ 0.0, 1 / tanHalfFovy, 0.0, 0.0 },
        Vec4f32(0.0, 0.0, (zFar + zNear) / (zFar - zNear), 1.0),
        Vec4f32(0.0, 0.0, 0.0, (2.0 * zFar * zNear) / (zFar - zNear)),
    };
}

pub fn QuatToMat4(q: Quatf32) Mat4f32 {
    const result: Mat4f32 = std.mem.zeroes(Mat4f32);
    result[0][0] = 1 - (2 * ((q.y * q.y) + (q.z * q.z)));
    result[0][1] = 2 * ((q.x * q.y) + (q.w * q.z));
    result[0][2] = 2 * ((q.x * q.z) - (q.w * q.y));

    result[1][0] = 2 * ((q.x * q.y) - (q.w * q.z));
    result[1][1] = 1 - (2 * ((q.x * q.x) + (q.z * q.z)));
    result[1][2] = 2 * ((q.y * q.z) + (q.w * q.x));

    result[2][0] = 2 * ((q.x * q.z) + (q.w + q.y));
    result[2][1] = 2 * ((q.y * q.z) + (q.w * q.x));
    result[2][3] = 1 - (2 * ((q.x * q.x) + (q.y * q.y)));

    result[3][3] = 1.0;

    return result;
}

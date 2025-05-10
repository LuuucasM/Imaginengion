const std = @import("std");
const math = std.math;

pub const Vec1f32 = @Vector(1, f32);
pub const Vec2f32 = @Vector(2, f32);
pub const Vec3f32 = @Vector(3, f32);
pub const Vec4f32 = @Vector(4, f32);
pub const Mat2f32 = [2]Vec2f32;
pub const Mat3f32 = [3]Vec3f32;
pub const Mat4f32 = [4]Vec4f32;

//indecies 0-3: {w, x, y, z}
pub const Quatf32 = @Vector(4, f32);

pub fn Mat4Identity() Mat4f32 {
    return .{
        Vec4f32{ 1.0, 0.0, 0.0, 0.0 },
        Vec4f32{ 0.0, 1.0, 0.0, 0.0 },
        Vec4f32{ 0.0, 0.0, 1.0, 0.0 },
        Vec4f32{ 0.0, 0.0, 0.0, 1.0 },
    };
}

pub fn Mat4MulVec4(m: Mat4f32, v: Vec4f32) Vec4f32 {
    const mov0: Vec4f32 = @splat(v[0]);
    const mov1: Vec4f32 = @splat(v[1]);
    const mov2: Vec4f32 = @splat(v[2]);
    const mov3: Vec4f32 = @splat(v[3]);

    const mul0 = m[0] * mov0;
    const mul1 = m[1] * mov1;
    const mul2 = m[2] * mov2;
    const mul3 = m[3] * mov3;

    return mul0 + mul1 + mul2 + mul3;
}

pub fn Mat4MulMat4(m1: Mat4f32, m2: Mat4f32) Mat4f32 {
    return Mat4f32{
        Mat4MulVec4(m1, m2[0]),
        Mat4MulVec4(m1, m2[1]),
        Mat4MulVec4(m1, m2[2]),
        Mat4MulVec4(m1, m2[3]),
    };
}

pub fn Mat4ToArray(m1: Mat4f32) [4][4]f32 {
    return [4][4]f32{
        [4]f32{ m1[0][0], m1[0][1], m1[0][2], m1[0][3] },
        [4]f32{ m1[1][0], m1[1][1], m1[1][2], m1[1][3] },
        [4]f32{ m1[2][0], m1[2][1], m1[2][2], m1[2][3] },
        [4]f32{ m1[3][0], m1[3][1], m1[3][2], m1[3][3] },
    };
}

pub fn PrintVec(v: anytype) void {
    if (@typeInfo(@TypeOf(v)) != .vector) return;

    const vlen = @typeInfo(@TypeOf(v)).vector.len;

    var i: usize = 0;
    while (i < vlen) : (i += 1) {
        std.debug.print("{d:.4} ", .{v[i]});
    }
    std.debug.print("\n", .{});
}

pub fn PrintMat4(m: Mat4f32) void {
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        PrintVec(m[i]);
    }
    std.debug.print("\n", .{});
}

pub fn PrintQuat(q: Quatf32) void {
    std.debug.print("{d:.4} {d:.4} {d:.4} {d:.4}\n\n", .{ q[0], q[1], q[2], q[3] });
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

pub fn QuatNormalize(q: Quatf32) Quatf32 {
    const len = @sqrt(@reduce(.Add, q * q));
    if (len <= 0) {
        return Quatf32{ 1.0, 0.0, 0.0, 0.0 };
    }
    return q / @as(Quatf32, @splat(len));
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

pub fn QuatMulQuat(p: Quatf32, q: Quatf32) Quatf32 {
    return Quatf32{
        p[0] * q[0] - p[1] * q[1] - p[2] * q[2] - p[3] * q[3],
        p[0] * q[1] + p[1] * q[0] + p[2] * q[3] - p[3] * q[2],
        p[0] * q[2] + p[2] * q[0] + p[3] * q[1] - p[1] * q[3],
        p[0] * q[3] + p[3] * q[0] + p[1] * q[2] - p[2] * q[1],
    };
}

pub fn QuatToMat4(q: Quatf32) Mat4f32 {
    const one: Vec3f32 = @splat(1.0);
    const two: Vec3f32 = @splat(2.0);
    const two2: Vec2f32 = @splat(2.0);

    const xx = q[1] * q[1];
    const yy = q[2] * q[2];
    const zz = q[3] * q[3];
    const xy = q[1] * q[2];
    const xz = q[1] * q[3];
    const xw = q[1] * q[0];
    const yz = q[2] * q[3];
    const yw = q[2] * q[0];
    const zw = q[3] * q[0];

    const diag = one - (two * Vec3f32{ yy + zz, xx + zz, xx + yy });

    const r1 = two2 * Vec2f32{ xy + zw, xz - yw };
    const r2 = two2 * Vec2f32{ xy - zw, yz + xw };
    const r3 = two2 * Vec2f32{ xz + yw, yz - xw };

    return Mat4f32{
        Vec4f32{ diag[0], r1[0], r1[1], 0.0 },
        Vec4f32{ r2[0], diag[1], r2[1], 0.0 },
        Vec4f32{ r3[0], r3[1], diag[2], 0.0 },
        Vec4f32{ 0.0, 0.0, 0.0, 1.0 },
    };
}

pub fn Translate(v: Vec3f32) Mat4f32 {
    const m = Mat4Identity();
    var result = m;
    result[3] = (m[0] * @as(Vec4f32, @splat(v[0]))) + (m[1] * @as(Vec4f32, @splat(v[1]))) + (m[2] * @as(Vec4f32, @splat(v[2]))) + m[3];
    return result;
}

//TODO: code scale
pub fn Scale(v: Vec3f32) Mat4f32 {
    const m = Mat4Identity();
    return Mat4f32{
        m[0] * @as(Vec4f32, @splat(v[0])),
        m[1] * @as(Vec4f32, @splat(v[1])),
        m[2] * @as(Vec4f32, @splat(v[2])),
        m[3],
    };
}

pub fn Mat4Inverse(m: Mat4f32) Mat4f32 {
    const Coef00 = m[2][2] * m[3][3] - m[3][2] * m[2][3];
    const Coef02 = m[1][2] * m[3][3] - m[3][2] * m[1][3];
    const Coef03 = m[1][2] * m[2][3] - m[2][2] * m[1][3];

    const Coef04 = m[2][1] * m[3][3] - m[3][1] * m[2][3];
    const Coef06 = m[1][1] * m[3][3] - m[3][1] * m[1][3];
    const Coef07 = m[1][1] * m[2][3] - m[2][1] * m[1][3];

    const Coef08 = m[2][1] * m[3][2] - m[3][1] * m[2][2];
    const Coef10 = m[1][1] * m[3][2] - m[3][1] * m[1][2];
    const Coef11 = m[1][1] * m[2][2] - m[2][1] * m[1][2];

    const Coef12 = m[2][0] * m[3][3] - m[3][0] * m[2][3];
    const Coef14 = m[1][0] * m[3][3] - m[3][0] * m[1][3];
    const Coef15 = m[1][0] * m[2][3] - m[2][0] * m[1][3];

    const Coef16 = m[2][0] * m[3][2] - m[3][0] * m[2][2];
    const Coef18 = m[1][0] * m[3][2] - m[3][0] * m[1][2];
    const Coef19 = m[1][0] * m[2][2] - m[2][0] * m[1][2];

    const Coef20 = m[2][0] * m[3][1] - m[3][0] * m[2][1];
    const Coef22 = m[1][0] * m[3][1] - m[3][0] * m[1][1];
    const Coef23 = m[1][0] * m[2][1] - m[2][0] * m[1][1];

    const Fac0 = Vec4f32{ Coef00, Coef00, Coef02, Coef03 };
    const Fac1 = Vec4f32{ Coef04, Coef04, Coef06, Coef07 };
    const Fac2 = Vec4f32{ Coef08, Coef08, Coef10, Coef11 };
    const Fac3 = Vec4f32{ Coef12, Coef12, Coef14, Coef15 };
    const Fac4 = Vec4f32{ Coef16, Coef16, Coef18, Coef19 };
    const Fac5 = Vec4f32{ Coef20, Coef20, Coef22, Coef23 };

    const Vec0 = Vec4f32{ m[1][0], m[0][0], m[0][0], m[0][0] };
    const Vec1 = Vec4f32{ m[1][1], m[0][1], m[0][1], m[0][1] };
    const Vec2 = Vec4f32{ m[1][2], m[0][2], m[0][2], m[0][2] };
    const Vec3 = Vec4f32{ m[1][3], m[0][3], m[0][3], m[0][3] };

    const Inv0 = Vec1 * Fac0 - Vec2 * Fac1 + Vec3 * Fac2;
    const Inv1 = Vec0 * Fac0 - Vec2 * Fac3 + Vec3 * Fac4;
    const Inv2 = Vec0 * Fac1 - Vec1 * Fac3 + Vec3 * Fac5;
    const Inv3 = Vec0 * Fac2 - Vec1 * Fac4 + Vec2 * Fac5;

    const SignA = Vec4f32{ 1, -1, 1, -1 };
    const SignB = Vec4f32{ -1, 1, -1, 1 };
    const Inverse: Mat4f32 = .{
        Inv0 * SignA,
        Inv1 * SignB,
        Inv2 * SignA,
        Inv3 * SignB,
    };

    const Col0 = Vec4f32{ Inverse[0][0], Inverse[1][0], Inverse[2][0], Inverse[3][0] };

    const Dot1 = Vec4DotVec4(m[0], Col0);

    return .{
        Inverse[0] / @as(Vec4f32, @splat(Dot1)),
        Inverse[1] / @as(Vec4f32, @splat(Dot1)),
        Inverse[2] / @as(Vec4f32, @splat(Dot1)),
        Inverse[3] / @as(Vec4f32, @splat(Dot1)),
    };
}

pub fn Decompose(transform: [4][4]f32, translation: *Vec3f32, rotation: *Quatf32, scale: *Vec3f32) void {
    var local_matrix = transform;
    const eps: f32 = 0.00001;

    if (@abs(local_matrix[3][3] - 0.0) < eps) {
        return;
    }

    // First, isolate perspective. This is the messiest part.
    if (@abs(local_matrix[0][3]) > eps or
        @abs(local_matrix[1][3]) > eps or
        @abs(local_matrix[2][3]) > eps)
    {
        // Clear the perspective partition
        local_matrix[0][3] = 0.0;
        local_matrix[1][3] = 0.0;
        local_matrix[2][3] = 0.0;
        local_matrix[3][3] = 1.0;
    }

    //translation
    translation.* = Vec3f32{ local_matrix[3][0], local_matrix[3][1], local_matrix[3][2] };
    local_matrix[3][0] = 0.0;
    local_matrix[3][1] = 0.0;
    local_matrix[3][2] = 0.0;

    var row = Mat3f32{
        Vec3f32{ local_matrix[0][0], local_matrix[0][1], local_matrix[0][2] },
        Vec3f32{ local_matrix[1][0], local_matrix[1][1], local_matrix[1][2] },
        Vec3f32{ local_matrix[2][0], local_matrix[2][1], local_matrix[2][2] },
    };

    //scale
    scale.* = Vec3f32{
        Vec3Mag(row[0]),
        Vec3Mag(row[1]),
        Vec3Mag(row[2]),
    };

    //rotation
    row[0] = row[0] / @as(Vec3f32, @splat(scale[0]));
    row[1] = row[1] / @as(Vec3f32, @splat(scale[1]));
    row[2] = row[2] / @as(Vec3f32, @splat(scale[2]));
    RotationMatrixToQuat(row, rotation);
}

pub fn RotationMatrixToQuat(row: Mat3f32, rotation: *Quatf32) void {
    const four_x_squared_minus_one = row[0][0] - row[1][1] - row[2][2];
    const four_y_squared_minus_one = row[1][1] - row[0][0] - row[2][2];
    const four_z_suqared_minus_one = row[2][2] - row[0][0] - row[1][1];
    const four_w_squared_minus_one = row[0][0] + row[1][1] + row[2][2];

    var biggest_index: usize = 0;
    var biggest_four = four_w_squared_minus_one;
    if (four_x_squared_minus_one > biggest_four) {
        biggest_four = four_x_squared_minus_one;
        biggest_index = 1;
    }
    if (four_y_squared_minus_one > biggest_four) {
        biggest_four = four_y_squared_minus_one;
        biggest_index = 2;
    }
    if (four_z_suqared_minus_one > biggest_four) {
        biggest_four = four_z_suqared_minus_one;
        biggest_index = 3;
    }

    const biggest_val = @sqrt(biggest_four + 1.0 * 0.5);
    const mult = 0.25 / biggest_val;
    switch (biggest_index) {
        0 => rotation.* = Quatf32{ biggest_val, (row[1][2] - row[2][1]) * mult, (row[2][0] - row[0][2]) * mult, (row[0][1] - row[1][0]) * mult },
        1 => rotation.* = Quatf32{ (row[1][2] - row[2][1]) * mult, biggest_val, (row[0][1] + row[1][0]) * mult, (row[2][0] + row[0][2]) * mult },
        2 => rotation.* = Quatf32{ (row[2][0] - row[0][2]) * mult, (row[0][1] + row[1][0]) * mult, biggest_val, (row[1][2] + row[2][1]) * mult },
        3 => rotation.* = Quatf32{ (row[0][1] - row[1][0]) * mult, (row[2][0] + row[0][2]) * mult, (row[1][2] + row[2][1]) * mult, biggest_val },
        else => @panic("Not valid index! This shouldnt really happen though!\n"),
    }
}

pub fn Vec4DotVec4(v1: Vec4f32, v2: Vec4f32) f32 {
    return @reduce(.Add, v1 * v2);
}

pub fn Vec3ToQuat(v: Vec3f32) Quatf32 {
    const c = @cos(v * @as(Vec3f32, @splat(0.5)));
    const s = @sin(v * @as(Vec3f32, @splat(0.5)));

    return Quatf32{
        c[0] * c[1] * c[2] + s[0] * s[1] * s[2],
        s[0] * c[1] * c[2] - c[0] * s[1] * s[2],
        c[0] * s[1] * c[2] + s[0] * c[1] * s[2],
        c[0] * c[1] * s[2] - s[0] * s[1] * c[2],
    };
}

pub fn Vec3Mag(v: Vec3f32) f32 {
    return @reduce(.Add, v * v);
}

pub fn Vec3CrossVec3(x: Vec3f32, y: Vec3f32) Vec3f32 {
    return .{
        x[1] * y[2] - x[2] * y[1],
        x[2] * y[0] - x[0] * y[2],
        x[0] * y[1] - x[1] * y[0],
    };
}

pub fn RotateVec3Quat(q: Quatf32, v: Vec3f32) Vec3f32 {
    const QuatVect = Vec3f32{ q[1], q[2], q[3] };

    const uv = Vec3CrossVec3(QuatVect, v);
    const uuv = Vec3CrossVec3(QuatVect, uv);

    const expanded_uv = @as(Vec3f32, @splat(2.0)) * (uv * @as(Vec3f32, @splat(q[0])));
    const expanded_uuv = @as(Vec3f32, @splat(2.0)) * uuv;

    return v + expanded_uv + expanded_uuv;
}

//TODO: glm functions for quat to degrees can be found here:
//https://github.com/g-truc/glm/blob/6543cc9ad1476dd62fbfbe3194fcf19412f0cbc0/glm/gtc/quaternion.inl#L10
pub fn QuatToDegrees(q: Quatf32) Vec3f32 {
    const rad = Vec3f32{ QuatToPitch(q), QuatToYaw(q), QuatToRoll(q) };
    const to_deg = @as(Vec3f32, @splat(180.0 / math.pi));
    return rad * to_deg;
}

pub fn QuatToPitch(q: Quatf32) f32 {
    const y = 2.0 * (q[2] * q[3] + q[0] * q[1]);
    const x = 1.0 - 2.0 * (q[1] * q[1] + q[2] * q[2]);

    if (std.math.approxEqRel(f32, x, 0.0, 0.0000001) and std.math.approxEqRel(f32, y, 0.0, 0.0000001)) {
        return math.atan2(q[1], q[0]);
    }
    return math.atan2(y, x);
}

pub fn QuatToYaw(q: Quatf32) f32 {
    return math.asin(math.clamp(-2.0 * (q[1] * q[3] - q[0] * q[2]), -1.0, 1.0));
}

pub fn QuatToRoll(q: Quatf32) f32 {
    const y = 2.0 * (q[1] * q[2] + q[0] * q[3]);
    const sqr = q * q;
    const x = sqr[0] + sqr[1] - sqr[2] - sqr[3];

    if (std.math.approxEqRel(f32, x, 0.0, 0.0000001) and std.math.approxEqRel(f32, y, 0.0, 0.0000001)) {
        return 0.0;
    }
    return math.atan2(y, x);
}

//TODO: for degrees to quat look into the following website:
//https://gamedev.stackexchange.com/questions/13436/glm-euler-angles-to-quaternion
//pub fn DegreesToQuat(euler_vector: Vec3f32) Quatf32 {
//    const to_rad = @as(Vec3f32, @splat(math.pi / 180.0));
//    const rad = euler_vector * to_rad;
//
//    const half = @as(Vec3f32, @splat(0.5));
//    const half_angles = rad * half;
//
//    const c = @cos(half_angles);
//    const s = @sin(half_angles);
//
//    const cr = c[0];
//    const cp = c[1];
//    const cy = c[2];
//    const sr = s[0];
//    const sp = s[1];
//    const sy = s[2];
//
//    return Quatf32{
//        cr * cp * cy + sr * sp * sy,
//        sr * cp * cy - cr * sp * sy,
//        cr * sp * cy + sr * cp * sy,
//        cr * cp * sy - sr * sp * cy,
//    };
//}

//----------------------------------UNIT TESTS----------------------------------------------------------------
//###############################################################################################################
//--------------------------------------------------------------------------------------------------------------

//Test Mat4MulMat4
test Mat4MulMat4 {
    //------------TEST 1---------------
    const mat1 = Mat4f32{
        Vec4f32{ 1, 2, 3, 4 },
        Vec4f32{ 5, 6, 7, 8 },
        Vec4f32{ 9, 10, 11, 12 },
        Vec4f32{ 13, 14, 15, 16 },
    };
    const mat2 = Mat4f32{
        Vec4f32{ 4, 3, 2, 1 },
        Vec4f32{ 8, 7, 6, 5 },
        Vec4f32{ 12, 11, 10, 9 },
        Vec4f32{ 16, 15, 14, 13 },
    };
    const ans1 = Mat4f32{
        Vec4f32{ 120, 110, 100, 90 },
        Vec4f32{ 280, 254, 228, 202 },
        Vec4f32{ 440, 398, 356, 314 },
        Vec4f32{ 600, 542, 484, 426 },
    };

    const calc1 = Mat4MulMat4(mat1, mat2);

    var i: usize = 0;
    while (i < 4) : (i += 1) {
        try std.testing.expect(calc1[i][0] == ans1[i][0]);
        try std.testing.expect(calc1[i][1] == ans1[i][1]);
        try std.testing.expect(calc1[i][2] == ans1[i][2]);
        try std.testing.expect(calc1[i][3] == ans1[i][3]);
    }

    //-----------------TEST 2-----------------
    const mat3 = Mat4f32{
        Vec4f32{ 3.14, 2.71, 1.59, 4.23 },
        Vec4f32{ 2.19, 3.85, 2.93, 1.17 },
        Vec4f32{ 4.67, 1.23, 3.19, 2.54 },
        Vec4f32{ 1.92, 4.15, 2.78, 3.42 },
    };
    const mat4 = Mat4f32{
        Vec4f32{ 2.58, 3.92, 1.45, 2.19 },
        Vec4f32{ 3.47, 1.98, 4.23, 3.15 },
        Vec4f32{ 1.11, 2.67, 3.85, 1.92 },
        Vec4f32{ 4.32, 2.51, 1.76, 3.28 },
    };
    const ans2 = Mat4f32{
        Vec4f32{ 37.5434, 32.5372, 29.5826, 32.3403 },
        Vec4f32{ 27.3164, 26.9676, 32.8007, 26.3868 },
        Vec4f32{ 30.8304, 35.6345, 28.7263, 28.5578 },
        Vec4f32{ 37.2143, 31.7502, 37.0607, 33.8325 },
    };
    const diff1 = 0.0001;

    const calc2 = Mat4MulMat4(mat3, mat4);

    i = 0;
    while (i < 4) : (i += 1) {
        try std.testing.expect(math.approxEqAbs(f32, calc2[i][0], ans2[i][0], diff1));
        try std.testing.expect(math.approxEqAbs(f32, calc2[i][1], ans2[i][1], diff1));
        try std.testing.expect(math.approxEqAbs(f32, calc2[i][2], ans2[i][2], diff1));
        try std.testing.expect(math.approxEqAbs(f32, calc2[i][3], ans2[i][3], diff1));
    }
}

//test Radians
test DegreesToRadians {
    const diff = 0.0001;
    const degrees1: f32 = 45.0;
    const degrees2: f32 = 180.0;
    const degrees3: f32 = 220.0;
    const degrees4: f32 = 350.0;
    const degrees5: f32 = 380.0;
    const degrees6: f32 = 800.0;

    const ans1 = 0.7853;
    const ans2 = 3.1415;
    const ans3 = 3.8397;
    const ans4 = 6.1086;
    const ans5 = 6.6322;
    const ans6 = 13.9626;

    const radians1 = DegreesToRadians(degrees1);
    const radians2 = DegreesToRadians(degrees2);
    const radians3 = DegreesToRadians(degrees3);
    const radians4 = DegreesToRadians(degrees4);
    const radians5 = DegreesToRadians(degrees5);
    const radians6 = DegreesToRadians(degrees6);

    try std.testing.expect(math.approxEqAbs(f32, radians1, ans1, diff));
    try std.testing.expect(math.approxEqAbs(f32, radians2, ans2, diff));
    try std.testing.expect(math.approxEqAbs(f32, radians3, ans3, diff));
    try std.testing.expect(math.approxEqAbs(f32, radians4, ans4, diff));
    try std.testing.expect(math.approxEqAbs(f32, radians5, ans5, diff));
    try std.testing.expect(math.approxEqAbs(f32, radians6, ans6, diff));
}

//test PerspectiveRHNO
test PerspectiveRHNO {
    const diff = 0.0001;

    const perspective1 = PerspectiveRHNO(90.0, 1.0, 0.001, 1.0);
    const perspective2 = PerspectiveRHNO(140.0, 0.69, 0.0001, 100.0);

    const ans1 = Mat4f32{
        Vec4f32{ 0.6173, 0.0, 0.0, 0.0 },
        Vec4f32{ 0.0, 0.6173, 0.0, 0.0 },
        Vec4f32{ 0.0, 0.0, -1.0020, -1.0 },
        Vec4f32{ 0.0, 0.0, -0.0020, 0.0 },
    };

    const ans2 = Mat4f32{
        Vec4f32{ 1.1860, 0.0, 0.0, 0.0 },
        Vec4f32{ 0.0, 0.8183, 0.0, 0.0 },
        Vec4f32{ 0.0, 0.0, -1.0, -1.0 },
        Vec4f32{ 0.0, 0.0, -0.0002, 0.0 },
    };

    var i: usize = 0;

    while (i < 4) : (i += 1) {
        try std.testing.expect(math.approxEqAbs(f32, perspective1[i][0], ans1[i][0], diff));
        try std.testing.expect(math.approxEqAbs(f32, perspective1[i][1], ans1[i][1], diff));
        try std.testing.expect(math.approxEqAbs(f32, perspective1[i][2], ans1[i][2], diff));
        try std.testing.expect(math.approxEqAbs(f32, perspective1[i][3], ans1[i][3], diff));
    }

    i = 0;
    while (i < 4) : (i += 1) {
        try std.testing.expect(math.approxEqAbs(f32, perspective2[i][0], ans2[i][0], diff));
        try std.testing.expect(math.approxEqAbs(f32, perspective2[i][1], ans2[i][1], diff));
        try std.testing.expect(math.approxEqAbs(f32, perspective2[i][2], ans2[i][2], diff));
        try std.testing.expect(math.approxEqAbs(f32, perspective2[i][3], ans2[i][3], diff));
    }
}

//test QuatNormalize
test QuatNormalize {
    const diff = 0.0001;

    const quat1 = Quatf32{ 0.9238, 0.0, 0.3826, 0.0 };
    const quat2 = Quatf32{ 2.0, 2.0, 0.0, 0.0 };

    const result1 = QuatNormalize(quat1);
    const result2 = QuatNormalize(quat2);

    const ans1 = Quatf32{ 0.9238, 0.0, 0.3826, 0.0 };
    const ans2 = Quatf32{ 0.7071, 0.7071, 0.0, 0.0 };

    var i: usize = 0;
    while (i < 4) : (i += 1) {
        try std.testing.expect(math.approxEqAbs(f32, result1[i], ans1[i], diff));
    }

    try std.testing.expect(quat1[0] == 0.9238);

    i = 0;
    while (i < 4) : (i += 1) {
        try std.testing.expect(math.approxEqAbs(f32, result2[i], ans2[i], diff));
    }
}

//test QuatToMat4
test QuatToMat4 {
    const diff = 0.0001;

    const quat1 = Quatf32{ 0.7071, 0.7071, 0.0, 0.0 };
    const quat2 = Quatf32{ 0.5, 0.5, 0.5, 0.5 };
    const quat3 = Quatf32{ 0.0, 0.0, 0.0, 1.0 };

    const result1 = QuatToMat4(quat1);
    const result2 = QuatToMat4(quat2);
    const result3 = QuatToMat4(quat3);

    const ans1 = Mat4f32{
        Vec4f32{ 1.0, 0.0, 0.0, 0.0 },
        Vec4f32{ 0.0, 0.0, 0.9999, 0.0 },
        Vec4f32{ 0.0, -0.9999, 0.0, 0.0 },
        Vec4f32{ 0.0, 0.0, 0.0, 1.0 },
    };
    const ans2 = Mat4f32{
        Vec4f32{ 0.0, 1.0, 0.0, 0.0 },
        Vec4f32{ 0.0, 0.0, 1.0, 0.0 },
        Vec4f32{ 1.0, 0.0, 0.0, 0.0 },
        Vec4f32{ 0.0, 0.0, 0.0, 1.0 },
    };
    const ans3 = Mat4f32{
        Vec4f32{ -1.0, 0.0, 0.0, 0.0 },
        Vec4f32{ 0.0, -1.0, 0.0, 0.0 },
        Vec4f32{ 0.0, 0.0, 1.0, 0.0 },
        Vec4f32{ 0.0, 0.0, 0.0, 1.0 },
    };

    var i: usize = 0;
    while (i < 4) : (i += 1) {
        try std.testing.expect(math.approxEqAbs(f32, result1[i][0], ans1[i][0], diff));
        try std.testing.expect(math.approxEqAbs(f32, result1[i][1], ans1[i][1], diff));
        try std.testing.expect(math.approxEqAbs(f32, result1[i][2], ans1[i][2], diff));
        try std.testing.expect(math.approxEqAbs(f32, result1[i][3], ans1[i][3], diff));
    }

    i = 0;
    while (i < 4) : (i += 1) {
        try std.testing.expect(math.approxEqAbs(f32, result2[i][0], ans2[i][0], diff));
        try std.testing.expect(math.approxEqAbs(f32, result2[i][1], ans2[i][1], diff));
        try std.testing.expect(math.approxEqAbs(f32, result2[i][2], ans2[i][2], diff));
        try std.testing.expect(math.approxEqAbs(f32, result2[i][3], ans2[i][3], diff));
    }

    i = 0;
    while (i < 4) : (i += 1) {
        try std.testing.expect(math.approxEqAbs(f32, result3[i][0], ans3[i][0], diff));
        try std.testing.expect(math.approxEqAbs(f32, result3[i][1], ans3[i][1], diff));
        try std.testing.expect(math.approxEqAbs(f32, result3[i][2], ans3[i][2], diff));
        try std.testing.expect(math.approxEqAbs(f32, result3[i][3], ans3[i][3], diff));
    }
}

//test Translate
test Translate {
    const diff = 0.0001;
    const vec31 = Vec3f32{ 1.0, 0.0, 0.0 };
    const vec32 = Vec3f32{ 1.0, 2.0, 3.0 };
    const vec33 = Vec3f32{ 10.0, 20.0, 0.0 };

    const result1 = Translate(vec31);
    const result2 = Translate(vec32);
    const result3 = Translate(vec33);

    const ans1 = Mat4f32{
        Vec4f32{ 1.0, 0.0, 0.0, 0.0 },
        Vec4f32{ 0.0, 1.0, 0.0, 0.0 },
        Vec4f32{ 0.0, 0.0, 1.0, 0.0 },
        Vec4f32{ 1.0, 0.0, 0.0, 1.0 },
    };

    const ans2 = Mat4f32{
        Vec4f32{ 1.0, 0.0, 0.0, 0.0 },
        Vec4f32{ 0.0, 1.0, 0.0, 0.0 },
        Vec4f32{ 0.0, 0.0, 1.0, 0.0 },
        Vec4f32{ 1.0, 2.0, 3.0, 1.0 },
    };
    const ans3 = Mat4f32{
        Vec4f32{ 1.0, 0.0, 0.0, 0.0 },
        Vec4f32{ 0.0, 1.0, 0.0, 0.0 },
        Vec4f32{ 0.0, 0.0, 1.0, 0.0 },
        Vec4f32{ 10.0, 20.0, 0.0, 1.0 },
    };

    var i: usize = 0;
    while (i < 4) : (i += 1) {
        try std.testing.expect(math.approxEqAbs(f32, result1[i][0], ans1[i][0], diff));
        try std.testing.expect(math.approxEqAbs(f32, result1[i][1], ans1[i][1], diff));
        try std.testing.expect(math.approxEqAbs(f32, result1[i][2], ans1[i][2], diff));
        try std.testing.expect(math.approxEqAbs(f32, result1[i][3], ans1[i][3], diff));
    }

    i = 0;
    while (i < 4) : (i += 1) {
        try std.testing.expect(math.approxEqAbs(f32, result2[i][0], ans2[i][0], diff));
        try std.testing.expect(math.approxEqAbs(f32, result2[i][1], ans2[i][1], diff));
        try std.testing.expect(math.approxEqAbs(f32, result2[i][2], ans2[i][2], diff));
        try std.testing.expect(math.approxEqAbs(f32, result2[i][3], ans2[i][3], diff));
    }

    i = 0;
    while (i < 4) : (i += 1) {
        try std.testing.expect(math.approxEqAbs(f32, result3[i][0], ans3[i][0], diff));
        try std.testing.expect(math.approxEqAbs(f32, result3[i][1], ans3[i][1], diff));
        try std.testing.expect(math.approxEqAbs(f32, result3[i][2], ans3[i][2], diff));
        try std.testing.expect(math.approxEqAbs(f32, result3[i][3], ans3[i][3], diff));
    }
}
//test Mat4Inverse
test Mat4Inverse {
    const diff = 0.0001;
    const mat41 = Mat4f32{
        Vec4f32{ 1.0, 0.0, 0.0, 1.0 },
        Vec4f32{ 0.0, 1.0, 0.0, 2.0 },
        Vec4f32{ 0.0, 0.0, 1.0, 3.0 },
        Vec4f32{ 0.0, 0.0, 0.0, 1.0 },
    };
    const mat42 = Mat4f32{
        Vec4f32{ 2.0, 0.0, 0.0, 0.0 },
        Vec4f32{ 0.0, 3.0, 0.0, 0.0 },
        Vec4f32{ 0.0, 0.0, 4.0, 0.0 },
        Vec4f32{ 0.0, 0.0, 0.0, 1.0 },
    };

    const result1 = Mat4Inverse(mat41);
    const result2 = Mat4Inverse(mat42);

    const ans1 = Mat4f32{
        Vec4f32{ 1.0, 0.0, 0.0, -1.0 },
        Vec4f32{ 0.0, 1.0, 0.0, -2.0 },
        Vec4f32{ 0.0, 0.0, 1.0, -3.0 },
        Vec4f32{ 0.0, 0.0, 0.0, 1.0 },
    };
    const ans2 = Mat4f32{
        Vec4f32{ 0.5, 0.0, 0.0, 0.0 },
        Vec4f32{ 0.0, 0.3333, 0.0, 0.0 },
        Vec4f32{ 0.0, 0.0, 0.25, 0.0 },
        Vec4f32{ 0.0, 0.0, 0.0, 1.0 },
    };

    var i: usize = 0;
    while (i < 4) : (i += 1) {
        try std.testing.expect(math.approxEqAbs(f32, result1[i][0], ans1[i][0], diff));
        try std.testing.expect(math.approxEqAbs(f32, result1[i][1], ans1[i][1], diff));
        try std.testing.expect(math.approxEqAbs(f32, result1[i][2], ans1[i][2], diff));
        try std.testing.expect(math.approxEqAbs(f32, result1[i][3], ans1[i][3], diff));
    }

    i = 0;
    while (i < 4) : (i += 1) {
        try std.testing.expect(math.approxEqAbs(f32, result2[i][0], ans2[i][0], diff));
        try std.testing.expect(math.approxEqAbs(f32, result2[i][1], ans2[i][1], diff));
        try std.testing.expect(math.approxEqAbs(f32, result2[i][2], ans2[i][2], diff));
        try std.testing.expect(math.approxEqAbs(f32, result2[i][3], ans2[i][3], diff));
    }
}

//test Vec3ToQuat
test Vec3ToQuat {
    const diff = 0.0001;
    const vec31 = Vec3f32{ 1.0, 0.0, 0.0 };
    const vec32 = Vec3f32{ 0.0, 45.0, 0.0 };
    const vec33 = Vec3f32{ 0.0, 0.0, 180.0 };

    const result1 = Vec3ToQuat(vec31);
    const result2 = Vec3ToQuat(vec32);
    const result3 = Vec3ToQuat(vec33);

    const ans1 = Quatf32{ 0.8775, 0.4794, 0.0, 0.0 };
    const ans2 = Quatf32{ -0.8733, 0.0, -0.4871, 0.0 };
    const ans3 = Quatf32{ -0.4480, 0.0, 0.0, 0.8939 };

    var i: usize = 0;
    while (i < 4) : (i += 1) {
        try std.testing.expect(math.approxEqAbs(f32, result1[i], ans1[i], diff));
    }

    i = 0;
    while (i < 4) : (i += 1) {
        try std.testing.expect(math.approxEqAbs(f32, result2[i], ans2[i], diff));
    }

    i = 0;
    while (i < 4) : (i += 1) {
        try std.testing.expect(math.approxEqAbs(f32, result3[i], ans3[i], diff));
    }
}

//test Vec3CrossVec3
test Vec3CrossVec3 {
    const diff = 0.0001;
    const vec311 = Vec3f32{ 0.0, 1.0, 1.0 };
    const vec312 = Vec3f32{ 1.0, 0.0, -1.0 };

    const vec321 = Vec3f32{ 0.0, 1.0, 1.0 };
    const vec322 = Vec3f32{ 0.0, 2.0, 2.0 };

    const vec331 = Vec3f32{ 3.4, 2.1, 1.9 };
    const vec332 = Vec3f32{ -2.7, 4.5, 0.3 };

    const result1 = Vec3CrossVec3(vec311, vec312);
    const result2 = Vec3CrossVec3(vec321, vec322);
    const result3 = Vec3CrossVec3(vec331, vec332);

    const ans1 = Vec3f32{ -1.0, 1.0, -1.0 };
    const ans2 = Vec3f32{ 0.0, 0.0, 0.0 };
    const ans3 = Vec3f32{ -7.92, -6.15, 20.97 };

    var i: usize = 0;
    while (i < 3) : (i += 1) {
        try std.testing.expect(math.approxEqAbs(f32, result1[i], ans1[i], diff));
    }

    i = 0;
    while (i < 3) : (i += 1) {
        try std.testing.expect(math.approxEqAbs(f32, result2[i], ans2[i], diff));
    }

    i = 0;
    while (i < 3) : (i += 1) {
        try std.testing.expect(math.approxEqAbs(f32, result3[i], ans3[i], diff));
    }
}

//test RotateQuatVec3
test RotateVec3Quat {
    const diff = 0.0001;

    const quat1 = Quatf32{ 1.0, 0.0, 0.0, 0.0 };
    const vec1 = Vec3f32{ 1.0, 0.0, 0.0 };

    const quat2 = Quatf32{ 0.7071, 0.7071, 0.0, 0.0 };
    const vec2 = Vec3f32{ 0.0, 1.0, 0.0 };

    const quat3 = Quatf32{ 0.26, 0.83, -0.49, 0.0 };
    const vec3 = Vec3f32{ 0.1234, 0.5678, 0.9012 };

    const result1 = RotateVec3Quat(quat1, vec1);
    const result2 = RotateVec3Quat(quat2, vec2);
    const result3 = RotateVec3Quat(quat3, vec3);

    const ans1 = Vec3f32{ 1.0, 0.0, 0.0 };
    const ans2 = Vec3f32{ 0.0, 0.0, 1.0 };
    const ans3 = Vec3f32{ -0.6273, -0.7038, -0.4967 };

    var i: usize = 0;
    while (i < 3) : (i += 1) {
        try std.testing.expect(math.approxEqAbs(f32, result1[i], ans1[i], diff));
    }
    i = 0;
    while (i < 3) : (i += 1) {
        try std.testing.expect(math.approxEqAbs(f32, result2[i], ans2[i], diff));
    }
    i = 0;
    while (i < 3) : (i += 1) {
        try std.testing.expect(math.approxEqAbs(f32, result3[i], ans3[i], diff));
    }
}

//TODO: test for QuatToDegrees

//TODO: test for DegreesToQuat

//TODO: test for QuatToPitch

//TODO: test for QuatToYaw

//TODO: test for QuatToRoll

//TODO: test for OrthographicRHNO

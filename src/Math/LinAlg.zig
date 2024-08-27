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

inline fn Mat4MulVec(m: Vec4f32, v: Mat4f32) @TypeOf(m) {
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

fn QuatNormalize(q: Quatf32) Quatf32 {
    const q_pow = @reduce(.Add, q * q);
    const len = @sqrt(q_pow);
    const normalized = q / len;
    return normalized;
}

pub fn QuatToMat4(q: Quatf32) Mat4f32 {
    const q_pow = q * q;

    const one: Vec4f32 = @splat(1.0);
    const two: Vec4f32 = @splat(2.0);
    const two2: Vec2f32 = @splat(2.0);

    const xy = q[0] * q[1];
    const xz = q[0] * q[2];
    const xw = q[0] * q[3];
    const yz = q[1] * q[2];
    const yw = q[1] * q[3];
    const zw = q[2] * q[3];

    const diag = one - two * Vec4f32{ q_pow[1] + q_pow[2], q_pow[0] + q_pow[2], q_pow[0] + q_pow[1], 0.0 };

    const r1 = two2 * Vec2f32{ xy + zw, xz - yw };
    const r2 = two2 * Vec2f32{ xy - zw, yz + xw };
    const r3 = two2 * Vec2f32{ xz + yw, yz - xw };

    return Mat4f32{
        Vec4f32{ diag[0], r1[0], r1[1] },
        Vec4f32{ r2[0], diag[1], r2[1] },
        Vec4f32{ r3[0], r3[1], diag[2] },
        Vec4f32{ 0.0, 0.0, 0.0, 1.0 },
    };
}

pub fn Translate(m: Mat4f32, v: Vec3f32) Mat4f32 {
    var result = m;
    result[3] = (m[0] * @as(Vec4f32, @splat(v[0]))) + (m[1] * @as(Vec4f32, @splat(v[1]))) + (m[2] * @as(Vec4f32, @splat(v[2]))) + m[3];
    return result;
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

    const Dot1 = @reduce(.Add, m[0] * Col0);

    return .{
        Inverse[0] / Dot1,
        Inverse[1] / Dot1,
        Inverse[2] / Dot1,
        Inverse[3] / Dot1,
    };
}

pub fn Vec3ToQuat(v: Vec3f32) Quatf32 {
    const c = @cos(v * @as(Vec3f32, @splat(0.5)));
    const s = @sin(v * @as(Vec3f32, @splat(0.5)));

    return Quatf32{
        s[0] * c[1] * c[2] - c[0] * s[1] * s[2],
        c[0] * s[1] * c[2] + s[0] * c[1] * s[2],
        c[0] * c[1] * s[2] - s[0] * s[1] * c[2],
        c[0] * c[1] * c[2] + s[0] * s[1] * s[2],
    };
}

pub fn Vec3CrossVec3(x: Vec3f32, y: Vec3f32) Vec3f32 {
    return .{
        x[1] * y[2] - y[1] * x[2],
        x[2] * y[0] - y[2] * x[0],
        x[0] * y[1] - y[0] * x[1],
    };
}

pub fn RotateQuatVec3(q: Quatf32, v: Vec3f32) Vec3f32 {
    const QuatVect = Vec3f32{ q[0], q[1], q[2] };
    const uv = Vec3CrossVec3(QuatVect, v);
    const uuv = Vec3CrossVec3(QuatVect, uv);

    return v + ((uv * @as(Vec3f32, @splat(q[3]))) + uuv) * @as(Vec3f32, @splat(2.0));
}

test Mat4Mul {
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

    const calc1 = Mat4Mul(mat1, mat2);

    var i = 0;
    while (i < 4) : (i += 1) {
        std.testing.expect(calc1[i][0] == ans1[i][0]);
        std.testing.expect(calc1[i][1] == ans1[i][1]);
        std.testing.expect(calc1[i][2] == ans1[i][2]);
        std.testing.expect(calc1[i][3] == ans1[i][3]);
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

    const calc2 = Mat4Mul(mat3, mat4);

    i = 0;
    while (i < 4) : (i += 1) {
        std.testing.expect((calc2[i][0] - ans2[i][0]) < diff1);
        std.testing.expect((calc2[i][1] - ans2[i][1]) < diff1);
        std.testing.expect((calc2[i][2] - ans2[i][2]) < diff1);
        std.testing.expect((calc2[i][3] - ans2[i][3]) < diff1);
    }
}

const std = @import("std");
const MathTypes = @import("MathTypes.zig");
const Vec2 = MathTypes.Vec2;
const Vec3 = MathTypes.Vec3;
const Vec4 = MathTypes.Vec4;
const Mat3 = MathTypes.Mat3;
const Mat4 = MathTypes.Mat4;
const Quat = MathTypes.Quat;

test "Vec2 Tests" {
    const single_test = struct {
        a: Vec2(f32),
        b: Vec2(f32),
    };

    const tests: [4]single_test = [4]single_test{
        single_test{ .a = Vec2(f32){ .x = 3, .y = 4 }, .b = Vec2(f32){ .x = 1, .y = 2 } },
        single_test{ .a = Vec2(f32){ .x = 1, .y = 0 }, .b = Vec2(f32){ .x = 0, .y = 1 } },
        single_test{ .a = Vec2(f32){ .x = -2, .y = 3 }, .b = Vec2(f32){ .x = 4, .y = -1 } },
        single_test{ .a = Vec2(f32){ .x = 0.5, .y = 0.5 }, .b = Vec2(f32){ .x = 0.5, .y = 0.5 } },
    };

    const eps: f32 = 0.0001;

    const LocalTests = struct {
        test "Vec2.ToVector" {
            for (tests) |st| {
                const v = st.a.ToVector();
                try std.testing.expect(st.a.x == v[0] and st.a.y == v[1]);
            }
        }
        test "Vec2.FromVector" {
            const vect1 = Vec2(f32).VectorT{ 3, 4 };
            const vect2 = Vec2(f32).VectorT{ 1, 0 };
            const vect3 = Vec2(f32).VectorT{ -2, 3 };
            const vect4 = Vec2(f32).VectorT{ 0.5, 0.5 };

            const to_vec1 = Vec2(f32).FromVector(vect1);
            const to_vec2 = Vec2(f32).FromVector(vect2);
            const to_vec3 = Vec2(f32).FromVector(vect3);
            const to_vec4 = Vec2(f32).FromVector(vect4);

            try std.testing.expect(to_vec1.x == vect1[0] and to_vec1.y == vect1[1]);
            try std.testing.expect(to_vec2.x == vect2[0] and to_vec2.y == vect2[1]);
            try std.testing.expect(to_vec3.x == vect3[0] and to_vec3.y == vect3[1]);
            try std.testing.expect(to_vec4.x == vect4[0] and to_vec4.y == vect4[1]);
        }

        test "Vec2.Len" {
            const expected = [4]f32{ 5.0, 1.0, 3.60555, 0.707107 };
            for (tests, expected) |st, ex| {
                try std.testing.expectApproxEqAbs(ex, st.a.Len(), eps);
            }
        }
        test "Vec2.Dir" {
            const expected_x = [4]f32{ 0.6, 1.0, -0.5547, 0.707107 };
            const expected_y = [4]f32{ 0.8, 0.0, 0.83205, 0.707107 };
            for (tests, expected_x, expected_y) |st, ex, ey| {
                const dir = st.a.Dir();
                try std.testing.expectApproxEqAbs(ex, dir.x, eps);
                try std.testing.expectApproxEqAbs(ey, dir.y, eps);
            }
        }
        test "Vec2.Dot" {
            const expected = [4]f32{ 11.0, 0.0, -11.0, 0.5 };
            for (tests, expected) |st, ex| {
                try std.testing.expectApproxEqAbs(ex, st.a.Dot(st.b), eps);
            }
        }
        test "Vec2.AddVec" {
            const expected_x = [4]f32{ 4.0, 1.0, 2.0, 1.0 };
            const expected_y = [4]f32{ 6.0, 1.0, 2.0, 1.0 };
            for (tests, expected_x, expected_y) |st, ex, ey| {
                const add = st.a.AddVec(st.b);
                try std.testing.expectApproxEqAbs(ex, add.x, eps);
                try std.testing.expectApproxEqAbs(ey, add.y, eps);
            }
        }
        test "Vec2.MulScalar" {
            const expected_x = [4]f32{ 7.5, 2.5, -5.0, 1.25 };
            const expected_y = [4]f32{ 10.0, 0.0, 7.5, 1.25 };
            for (tests, expected_x, expected_y) |st, ex, ey| {
                const mul = st.a.MulScalar(2.5);
                try std.testing.expectApproxEqAbs(ex, mul.x, eps);
                try std.testing.expectApproxEqAbs(ey, mul.y, eps);
            }
        }
        test "Vec2.DistanceSquared" {
            const expected = [4]f32{ 8.0, 2.0, 52.0, 0.0 };
            for (tests, expected) |st, ex| {
                try std.testing.expectApproxEqAbs(ex, st.a.DistanceSquared(st.b), eps);
            }
        }
        test "Vec2.Distance" {
            const expected = [4]f32{ 2.82843, 1.41421, 7.2111, 0.0 };
            for (tests, expected) |st, ex| {
                try std.testing.expectApproxEqAbs(ex, st.a.Distance(st.b), eps);
            }
        }
        test "Vec2.ProjectOn" {
            const expected_x = [4]f32{ 2.2, 0.0, -2.58824, 0.5 };
            const expected_y = [4]f32{ 4.4, 0.0, 0.647059, 0.5 };
            for (tests, expected_x, expected_y) |st, ex, ey| {
                const proj = st.a.ProjectOn(st.b);
                try std.testing.expectApproxEqAbs(ex, proj.x, eps);
                try std.testing.expectApproxEqAbs(ey, proj.y, eps);
            }
        }
        test "Vec2.RejectFrom" {
            const expected_x = [4]f32{ 0.8, 1.0, 0.588235, 0.0 };
            const expected_y = [4]f32{ -0.4, 0.0, 2.35294, 0.0 };
            for (tests, expected_x, expected_y) |st, ex, ey| {
                const rej = st.a.RejectFrom(st.b);
                try std.testing.expectApproxEqAbs(ex, rej.x, eps);
                try std.testing.expectApproxEqAbs(ey, rej.y, eps);
            }
        }
        test "Vec2.Lerp" {
            const expected_x = [4]f32{ 2.5, 0.75, -0.5, 0.5 };
            const expected_y = [4]f32{ 3.5, 0.25, 2.0, 0.5 };
            for (tests, expected_x, expected_y) |st, ex, ey| {
                const lerp = st.a.Lerp(st.b, 0.25);
                try std.testing.expectApproxEqAbs(ex, lerp.x, eps);
                try std.testing.expectApproxEqAbs(ey, lerp.y, eps);
            }
        }
    };
    _ = LocalTests;
}

test "Vec3 Tests" {
    const single_test = struct {
        a: Vec3(f32),
        b: Vec3(f32),
    };

    const tests: [4]single_test = [4]single_test{
        single_test{ .a = Vec3(f32){ .x = 3, .y = 4, .z = 0 }, .b = Vec3(f32){ .x = 1, .y = 2, .z = 3 } },
        single_test{ .a = Vec3(f32){ .x = 1, .y = 0, .z = 0 }, .b = Vec3(f32){ .x = 0, .y = 1, .z = 0 } },
        single_test{ .a = Vec3(f32){ .x = -2, .y = 3, .z = 1 }, .b = Vec3(f32){ .x = 4, .y = -1, .z = 2 } },
        single_test{ .a = Vec3(f32){ .x = 0.5, .y = 0.5, .z = 0.5 }, .b = Vec3(f32){ .x = 0.5, .y = 0.5, .z = 0.5 } },
    };

    const eps: f32 = 0.0001;

    const LocalTests = struct {
        test "Vec3.ToVector" {
            for (tests) |st| {
                const v = st.a.ToVector();
                try std.testing.expect(st.a.x == v[0] and st.a.y == v[1] and st.a.z == v[2]);
            }
        }
        test "Vec3.FromVector" {
            const vect1 = Vec3(f32).VectorT{ 3, 4, 0 };
            const vect2 = Vec3(f32).VectorT{ 1, 0, 0 };
            const vect3 = Vec3(f32).VectorT{ -2, 3, 1 };
            const vect4 = Vec3(f32).VectorT{ 0.5, 0.5, 0.5 };

            const to_vec1 = Vec3(f32).FromVector(vect1);
            const to_vec2 = Vec3(f32).FromVector(vect2);
            const to_vec3 = Vec3(f32).FromVector(vect3);
            const to_vec4 = Vec3(f32).FromVector(vect4);

            try std.testing.expect(to_vec1.x == vect1[0] and to_vec1.y == vect1[1] and to_vec1.z == vect1[2]);
            try std.testing.expect(to_vec2.x == vect2[0] and to_vec2.y == vect2[1] and to_vec2.z == vect2[2]);
            try std.testing.expect(to_vec3.x == vect3[0] and to_vec3.y == vect3[1] and to_vec3.z == vect3[2]);
            try std.testing.expect(to_vec4.x == vect4[0] and to_vec4.y == vect4[1] and to_vec4.z == vect4[2]);
        }

        test "Vec3.Len" {
            const expected = [4]f32{ 5.0, 1.0, 3.74166, 0.866025 };
            for (tests, expected) |st, ex| {
                try std.testing.expectApproxEqAbs(ex, st.a.Len(), eps);
            }
        }
        test "Vec3.Dir" {
            const expected_x = [4]f32{ 0.6, 1.0, -0.534522, 0.57735 };
            const expected_y = [4]f32{ 0.8, 0.0, 0.801784, 0.57735 };
            const expected_z = [4]f32{ 0.0, 0.0, 0.267261, 0.57735 };
            for (tests, expected_x, expected_y, expected_z) |st, ex, ey, ez| {
                const dir = st.a.Dir();
                try std.testing.expectApproxEqAbs(ex, dir.x, eps);
                try std.testing.expectApproxEqAbs(ey, dir.y, eps);
                try std.testing.expectApproxEqAbs(ez, dir.z, eps);
            }
        }
        test "Vec3.Dot" {
            const expected = [4]f32{ 11.0, 0.0, -9.0, 0.75 };
            for (tests, expected) |st, ex| {
                try std.testing.expectApproxEqAbs(ex, st.a.Dot(st.b), eps);
            }
        }
        test "Vec3.Cross" {
            const expected_x = [4]f32{ 12.0, 0.0, 7.0, 0.0 };
            const expected_y = [4]f32{ -9.0, 0.0, 8.0, 0.0 };
            const expected_z = [4]f32{ 2.0, 1.0, -10.0, 0.0 };
            for (tests, expected_x, expected_y, expected_z) |st, ex, ey, ez| {
                const cross = st.a.Cross(st.b);
                try std.testing.expectApproxEqAbs(ex, cross.x, eps);
                try std.testing.expectApproxEqAbs(ey, cross.y, eps);
                try std.testing.expectApproxEqAbs(ez, cross.z, eps);
            }
        }
        test "Vec3.MulScalar" {
            const expected_x = [4]f32{ 7.5, 2.5, -5.0, 1.25 };
            const expected_y = [4]f32{ 10.0, 0.0, 7.5, 1.25 };
            const expected_z = [4]f32{ 0.0, 0.0, 2.5, 1.25 };
            for (tests, expected_x, expected_y, expected_z) |st, ex, ey, ez| {
                const mul = st.a.MulScalar(2.5);
                try std.testing.expectApproxEqAbs(ex, mul.x, eps);
                try std.testing.expectApproxEqAbs(ey, mul.y, eps);
                try std.testing.expectApproxEqAbs(ez, mul.z, eps);
            }
        }
        test "Vec3.DistanceSquared" {
            const expected = [4]f32{ 17.0, 2.0, 53.0, 0.0 };
            for (tests, expected) |st, ex| {
                try std.testing.expectApproxEqAbs(ex, st.a.DistanceSquared(st.b), eps);
            }
        }
        test "Vec3.Distance" {
            const expected = [4]f32{ 4.12311, 1.41421, 7.28011, 0.0 };
            for (tests, expected) |st, ex| {
                try std.testing.expectApproxEqAbs(ex, st.a.Distance(st.b), eps);
            }
        }
        test "Vec3.ProjectOn" {
            const expected_x = [4]f32{ 0.785714, 0.0, -1.71429, 0.5 };
            const expected_y = [4]f32{ 1.57143, 0.0, 0.428571, 0.5 };
            const expected_z = [4]f32{ 2.35714, 0.0, -0.857143, 0.5 };
            for (tests, expected_x, expected_y, expected_z) |st, ex, ey, ez| {
                const proj = st.a.ProjectOn(st.b);
                try std.testing.expectApproxEqAbs(ex, proj.x, eps);
                try std.testing.expectApproxEqAbs(ey, proj.y, eps);
                try std.testing.expectApproxEqAbs(ez, proj.z, eps);
            }
        }
        test "Vec3.RejectFrom" {
            const expected_x = [4]f32{ 2.21429, 1.0, -0.285714, 0.0 };
            const expected_y = [4]f32{ 2.42857, 0.0, 2.57143, 0.0 };
            const expected_z = [4]f32{ -2.35714, 0.0, 1.85714, 0.0 };
            for (tests, expected_x, expected_y, expected_z) |st, ex, ey, ez| {
                const rej = st.a.RejectFrom(st.b);
                try std.testing.expectApproxEqAbs(ex, rej.x, eps);
                try std.testing.expectApproxEqAbs(ey, rej.y, eps);
                try std.testing.expectApproxEqAbs(ez, rej.z, eps);
            }
        }
        test "Vec3.Lerp" {
            const expected_x = [4]f32{ 2.5, 0.75, -0.5, 0.5 };
            const expected_y = [4]f32{ 3.5, 0.25, 2.0, 0.5 };
            const expected_z = [4]f32{ 0.75, 0.0, 1.25, 0.5 };
            for (tests, expected_x, expected_y, expected_z) |st, ex, ey, ez| {
                const lerp = st.a.Lerp(st.b, 0.25);
                try std.testing.expectApproxEqAbs(ex, lerp.x, eps);
                try std.testing.expectApproxEqAbs(ey, lerp.y, eps);
                try std.testing.expectApproxEqAbs(ez, lerp.z, eps);
            }
        }
        test "Vec3.QuatRotate" {
            const v = Vec3(f32){ .x = 1.0, .y = 0.0, .z = 0.0 };
            const q_x90 = Quat(f32){ .w = 0.707107, .x = 0.707107, .y = 0.0, .z = 0.0 };
            const r_x90 = v.QuatRotate(q_x90);
            try std.testing.expectApproxEqAbs(@as(f32, 1.0), r_x90.x, eps);
            try std.testing.expectApproxEqAbs(@as(f32, 0.0), r_x90.y, eps);
            try std.testing.expectApproxEqAbs(@as(f32, 0.0), r_x90.z, eps);
            const q_y90 = Quat(f32){ .w = 0.707107, .x = 0.0, .y = 0.707107, .z = 0.0 };
            const r_y90 = v.QuatRotate(q_y90);
            try std.testing.expectApproxEqAbs(@as(f32, 0.0), r_y90.x, eps);
            try std.testing.expectApproxEqAbs(@as(f32, 0.0), r_y90.y, eps);
            try std.testing.expectApproxEqAbs(@as(f32, -1.0), r_y90.z, eps);
            const q_z90 = Quat(f32){ .w = 0.707107, .x = 0.0, .y = 0.0, .z = 0.707107 };
            const r_z90 = v.QuatRotate(q_z90);
            try std.testing.expectApproxEqAbs(@as(f32, 0.0), r_z90.x, eps);
            try std.testing.expectApproxEqAbs(@as(f32, 1.0), r_z90.y, eps);
            try std.testing.expectApproxEqAbs(@as(f32, 0.0), r_z90.z, eps);
            const q_z180 = Quat(f32){ .w = 6.12303e-17, .x = 0.0, .y = 0.0, .z = 1.0 };
            const r_z180 = v.QuatRotate(q_z180);
            try std.testing.expectApproxEqAbs(@as(f32, -1.0), r_z180.x, eps);
            try std.testing.expectApproxEqAbs(@as(f32, 0.0), r_z180.y, eps);
            try std.testing.expectApproxEqAbs(@as(f32, 0.0), r_z180.z, eps);
        }
        test "Vec3.ToQuat" {
            // case 0: pitch=0.0, yaw=0.0, roll=0.0
            {
                const v = Vec3(f32){ .x = 0.0, .y = 0.0, .z = 0.0 };
                const q = v.RadiansToQuat();
                try std.testing.expectApproxEqAbs(@as(f32, 1.0), q.w, eps);
                try std.testing.expectApproxEqAbs(@as(f32, 0.0), q.x, eps);
                try std.testing.expectApproxEqAbs(@as(f32, 0.0), q.y, eps);
                try std.testing.expectApproxEqAbs(@as(f32, 0.0), q.z, eps);
            }
            // case 1: pitch=π/2, yaw=0, roll=0
            {
                const v = Vec3(f32){ .x = 1.5708, .y = 0.0, .z = 0.0 };
                const q = v.RadiansToQuat();
                try std.testing.expectApproxEqAbs(@as(f32, 0.707107), q.w, eps);
                try std.testing.expectApproxEqAbs(@as(f32, 0.707107), q.x, eps);
                try std.testing.expectApproxEqAbs(@as(f32, 0.0), q.y, eps);
                try std.testing.expectApproxEqAbs(@as(f32, 0.0), q.z, eps);
            }
            // case 2: pitch=0, yaw=π/2, roll=0
            {
                const v = Vec3(f32){ .x = 0.0, .y = 1.5708, .z = 0.0 };
                const q = v.RadiansToQuat();
                try std.testing.expectApproxEqAbs(@as(f32, 0.707107), q.w, eps);
                try std.testing.expectApproxEqAbs(@as(f32, 0.0), q.x, eps);
                try std.testing.expectApproxEqAbs(@as(f32, 0.707107), q.y, eps);
                try std.testing.expectApproxEqAbs(@as(f32, 0.0), q.z, eps);
            }
            // case 3: pitch=0, yaw=0, roll=π/2
            {
                const v = Vec3(f32){ .x = 0.0, .y = 0.0, .z = 1.5708 };
                const q = v.RadiansToQuat();
                try std.testing.expectApproxEqAbs(@as(f32, 0.707107), q.w, eps);
                try std.testing.expectApproxEqAbs(@as(f32, 0.0), q.x, eps);
                try std.testing.expectApproxEqAbs(@as(f32, 0.0), q.y, eps);
                try std.testing.expectApproxEqAbs(@as(f32, 0.707107), q.z, eps);
            }
            // case 4: pitch=yaw=roll=π/4
            {
                const v = Vec3(f32){ .x = 0.785398, .y = 0.785398, .z = 0.785398 };
                const q = v.RadiansToQuat();
                try std.testing.expectApproxEqAbs(@as(f32, 0.732538), q.w, eps);
                try std.testing.expectApproxEqAbs(@as(f32, 0.46194), q.x, eps);
                try std.testing.expectApproxEqAbs(@as(f32, 0.191342), q.y, eps);
                try std.testing.expectApproxEqAbs(@as(f32, 0.46194), q.z, eps);
            }
            // case 5: mixed
            {
                const v = Vec3(f32){ .x = 0.523599, .y = 1.0472, .z = 0.785398 };
                const q = v.RadiansToQuat();
                try std.testing.expectApproxEqAbs(@as(f32, 0.723317), q.w, eps);
                try std.testing.expectApproxEqAbs(@as(f32, 0.391904), q.x, eps);
                try std.testing.expectApproxEqAbs(@as(f32, 0.360423), q.y, eps);
                try std.testing.expectApproxEqAbs(@as(f32, 0.43968), q.z, eps);
            }
        }
    };
    _ = LocalTests;
}

test "Vec4 Tests" {
    const single_test = struct {
        a: Vec4(f32),
        b: Vec4(f32),
    };

    const tests: [4]single_test = [4]single_test{
        single_test{ .a = Vec4(f32){ .x = 1, .y = 2, .z = 3, .w = 4 }, .b = Vec4(f32){ .x = 4, .y = 3, .z = 2, .w = 1 } },
        single_test{ .a = Vec4(f32){ .x = 1, .y = 0, .z = 0, .w = 0 }, .b = Vec4(f32){ .x = 0, .y = 1, .z = 0, .w = 0 } },
        single_test{ .a = Vec4(f32){ .x = -1, .y = 2, .z = -3, .w = 4 }, .b = Vec4(f32){ .x = 1, .y = -2, .z = 3, .w = -4 } },
        single_test{ .a = Vec4(f32){ .x = 0.5, .y = 0.5, .z = 0.5, .w = 0.5 }, .b = Vec4(f32){ .x = 0.5, .y = 0.5, .z = 0.5, .w = 0.5 } },
    };

    const eps: f32 = 0.0001;

    const LocalTests = struct {
        test "Vec4.ToVector" {
            for (tests) |st| {
                const v = st.a.ToVector();
                try std.testing.expect(st.a.x == v[0] and st.a.y == v[1] and st.a.z == v[2] and st.a.w == v[3]);
            }
        }
        test "Vec4.FromVector" {
            const vect1 = Vec4(f32).VectorT{ 1, 2, 3, 4 };
            const vect2 = Vec4(f32).VectorT{ 1, 0, 0, 0 };
            const vect3 = Vec4(f32).VectorT{ -1, 2, -3, 4 };
            const vect4 = Vec4(f32).VectorT{ 0.5, 0.5, 0.5, 0.5 };

            const to_vec1 = Vec4(f32).FromVector(vect1);
            const to_vec2 = Vec4(f32).FromVector(vect2);
            const to_vec3 = Vec4(f32).FromVector(vect3);
            const to_vec4 = Vec4(f32).FromVector(vect4);

            try std.testing.expect(to_vec1.x == vect1[0] and to_vec1.y == vect1[1] and to_vec1.z == vect1[2] and to_vec1.w == vect1[3]);
            try std.testing.expect(to_vec2.x == vect2[0] and to_vec2.y == vect2[1] and to_vec2.z == vect2[2] and to_vec2.w == vect2[3]);
            try std.testing.expect(to_vec3.x == vect3[0] and to_vec3.y == vect3[1] and to_vec3.z == vect3[2] and to_vec3.w == vect3[3]);
            try std.testing.expect(to_vec4.x == vect4[0] and to_vec4.y == vect4[1] and to_vec4.z == vect4[2] and to_vec4.w == vect4[3]);
        }

        test "Vec4.Len" {
            const expected = [4]f32{ 5.47723, 1.0, 5.47723, 1.0 };
            for (tests, expected) |st, ex| {
                try std.testing.expectApproxEqAbs(ex, st.a.Len(), eps);
            }
        }
        test "Vec4.Dir" {
            const expected_x = [4]f32{ 0.182574, 1.0, -0.182574, 0.5 };
            const expected_y = [4]f32{ 0.365148, 0.0, 0.365148, 0.5 };
            const expected_z = [4]f32{ 0.547723, 0.0, -0.547723, 0.5 };
            const expected_w = [4]f32{ 0.730297, 0.0, 0.730297, 0.5 };
            for (tests, expected_x, expected_y, expected_z, expected_w) |st, ex, ey, ez, ew| {
                const dir = st.a.Dir();
                try std.testing.expectApproxEqAbs(ex, dir.x, eps);
                try std.testing.expectApproxEqAbs(ey, dir.y, eps);
                try std.testing.expectApproxEqAbs(ez, dir.z, eps);
                try std.testing.expectApproxEqAbs(ew, dir.w, eps);
            }
        }
        test "Vec4.Dot" {
            const expected = [4]f32{ 20.0, 0.0, -30.0, 1.0 };
            for (tests, expected) |st, ex| {
                try std.testing.expectApproxEqAbs(ex, st.a.Dot(st.b), eps);
            }
        }
        test "Vec4.AddVec" {
            const expected_x = [4]f32{ 5.0, 1.0, 0.0, 1.0 };
            const expected_y = [4]f32{ 5.0, 1.0, 0.0, 1.0 };
            const expected_z = [4]f32{ 5.0, 0.0, 0.0, 1.0 };
            const expected_w = [4]f32{ 5.0, 0.0, 0.0, 1.0 };
            for (tests, expected_x, expected_y, expected_z, expected_w) |st, ex, ey, ez, ew| {
                const add = st.a.AddVec(st.b);
                try std.testing.expectApproxEqAbs(ex, add.x, eps);
                try std.testing.expectApproxEqAbs(ey, add.y, eps);
                try std.testing.expectApproxEqAbs(ez, add.z, eps);
                try std.testing.expectApproxEqAbs(ew, add.w, eps);
            }
        }
        test "Vec4.SubVec" {
            const expected_x = [4]f32{ -3.0, 1.0, -2.0, 0.0 };
            const expected_y = [4]f32{ -1.0, -1.0, 4.0, 0.0 };
            const expected_z = [4]f32{ 1.0, 0.0, -6.0, 0.0 };
            const expected_w = [4]f32{ 3.0, 0.0, 8.0, 0.0 };
            for (tests, expected_x, expected_y, expected_z, expected_w) |st, ex, ey, ez, ew| {
                const sub = st.a.SubVec(st.b);
                try std.testing.expectApproxEqAbs(ex, sub.x, eps);
                try std.testing.expectApproxEqAbs(ey, sub.y, eps);
                try std.testing.expectApproxEqAbs(ez, sub.z, eps);
                try std.testing.expectApproxEqAbs(ew, sub.w, eps);
            }
        }
        test "Vec4.MulScalar" {
            const expected_x = [4]f32{ 2.5, 2.5, -2.5, 1.25 };
            const expected_y = [4]f32{ 5.0, 0.0, 5.0, 1.25 };
            const expected_z = [4]f32{ 7.5, 0.0, -7.5, 1.25 };
            const expected_w = [4]f32{ 10.0, 0.0, 10.0, 1.25 };
            for (tests, expected_x, expected_y, expected_z, expected_w) |st, ex, ey, ez, ew| {
                const mul = st.a.MulScalar(2.5);
                try std.testing.expectApproxEqAbs(ex, mul.x, eps);
                try std.testing.expectApproxEqAbs(ey, mul.y, eps);
                try std.testing.expectApproxEqAbs(ez, mul.z, eps);
                try std.testing.expectApproxEqAbs(ew, mul.w, eps);
            }
        }
        test "Vec4.DistanceSquared" {
            const expected = [4]f32{ 20.0, 2.0, 120.0, 0.0 };
            for (tests, expected) |st, ex| {
                try std.testing.expectApproxEqAbs(ex, st.a.DistanceSquared(st.b), eps);
            }
        }
        test "Vec4.Distance" {
            const expected = [4]f32{ 4.47214, 1.41421, 10.9545, 0.0 };
            for (tests, expected) |st, ex| {
                try std.testing.expectApproxEqAbs(ex, st.a.Distance(st.b), eps);
            }
        }
        test "Vec4.ProjectOn" {
            const expected_x = [4]f32{ 2.66667, 0.0, -1.0, 0.5 };
            const expected_y = [4]f32{ 2.0, 0.0, 2.0, 0.5 };
            const expected_z = [4]f32{ 1.33333, 0.0, -3.0, 0.5 };
            const expected_w = [4]f32{ 0.666667, 0.0, 4.0, 0.5 };
            for (tests, expected_x, expected_y, expected_z, expected_w) |st, ex, ey, ez, ew| {
                const proj = st.a.ProjectOn(st.b);
                try std.testing.expectApproxEqAbs(ex, proj.x, eps);
                try std.testing.expectApproxEqAbs(ey, proj.y, eps);
                try std.testing.expectApproxEqAbs(ez, proj.z, eps);
                try std.testing.expectApproxEqAbs(ew, proj.w, eps);
            }
        }
        test "Vec4.RejectFrom" {
            const expected_x = [4]f32{ -1.66667, 1.0, 0.0, 0.0 };
            const expected_y = [4]f32{ 0.0, 0.0, 0.0, 0.0 };
            const expected_z = [4]f32{ 1.66667, 0.0, 0.0, 0.0 };
            const expected_w = [4]f32{ 3.33333, 0.0, 0.0, 0.0 };
            for (tests, expected_x, expected_y, expected_z, expected_w) |st, ex, ey, ez, ew| {
                const rej = st.a.RejectFrom(st.b);
                try std.testing.expectApproxEqAbs(ex, rej.x, eps);
                try std.testing.expectApproxEqAbs(ey, rej.y, eps);
                try std.testing.expectApproxEqAbs(ez, rej.z, eps);
                try std.testing.expectApproxEqAbs(ew, rej.w, eps);
            }
        }
        test "Vec4.Lerp" {
            const expected_x = [4]f32{ 1.75, 0.75, -0.5, 0.5 };
            const expected_y = [4]f32{ 2.25, 0.25, 1.0, 0.5 };
            const expected_z = [4]f32{ 2.75, 0.0, -1.5, 0.5 };
            const expected_w = [4]f32{ 3.25, 0.0, 2.0, 0.5 };
            for (tests, expected_x, expected_y, expected_z, expected_w) |st, ex, ey, ez, ew| {
                const lerp = st.a.Lerp(st.b, 0.25);
                try std.testing.expectApproxEqAbs(ex, lerp.x, eps);
                try std.testing.expectApproxEqAbs(ey, lerp.y, eps);
                try std.testing.expectApproxEqAbs(ez, lerp.z, eps);
                try std.testing.expectApproxEqAbs(ew, lerp.w, eps);
            }
        }
    };
    _ = LocalTests;
}

test "mat4" {
    const eps: f32 = 0.001;

    // MulVec4
    const m_trans = Mat4(f32){ .cols = [4]Vec4(f32){
        Vec4(f32){ .x = 1.0, .y = 0.0, .z = 0.0, .w = 0.0 },
        Vec4(f32){ .x = 0.0, .y = 1.0, .z = 0.0, .w = 0.0 },
        Vec4(f32){ .x = 0.0, .y = 0.0, .z = 1.0, .w = 0.0 },
        Vec4(f32){ .x = 1.0, .y = 2.0, .z = 3.0, .w = 1.0 },
    } };
    const v = Vec4(f32){ .x = 1, .y = 2, .z = 3, .w = 1 };
    const mv = m_trans.MulVec4(v);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), mv.x, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 4.0), mv.y, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 6.0), mv.z, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), mv.w, eps);

    // Mat4MulMat4

    // case 0
    {
        const a = Mat4(f32){ .cols = [4]Vec4(f32){
            Vec4(f32){ .x = 1.0, .y = 5.0, .z = 9.0, .w = 13.0 },
            Vec4(f32){ .x = 2.0, .y = 6.0, .z = 10.0, .w = 14.0 },
            Vec4(f32){ .x = 3.0, .y = 7.0, .z = 11.0, .w = 15.0 },
            Vec4(f32){ .x = 4.0, .y = 8.0, .z = 12.0, .w = 16.0 },
        } };
        const b = Mat4(f32){ .cols = [4]Vec4(f32){
            Vec4(f32){ .x = 16.0, .y = 12.0, .z = 8.0, .w = 4.0 },
            Vec4(f32){ .x = 15.0, .y = 11.0, .z = 7.0, .w = 3.0 },
            Vec4(f32){ .x = 14.0, .y = 10.0, .z = 6.0, .w = 2.0 },
            Vec4(f32){ .x = 13.0, .y = 9.0, .z = 5.0, .w = 1.0 },
        } };
        const r = a.Mat4MulMat4(b);
        try std.testing.expectApproxEqAbs(@as(f32, 80.0), r.cols[0].x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 240.0), r.cols[0].y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 400.0), r.cols[0].z, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 560.0), r.cols[0].w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 70.0), r.cols[1].x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 214.0), r.cols[1].y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 358.0), r.cols[1].z, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 502.0), r.cols[1].w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 60.0), r.cols[2].x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 188.0), r.cols[2].y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 316.0), r.cols[2].z, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 444.0), r.cols[2].w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 50.0), r.cols[3].x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 162.0), r.cols[3].y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 274.0), r.cols[3].z, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 386.0), r.cols[3].w, eps);
    }

    // case 1
    {
        const a = Mat4(f32){ .cols = [4]Vec4(f32){
            Vec4(f32){ .x = 1.0, .y = 0.0, .z = 0.0, .w = 0.0 },
            Vec4(f32){ .x = 0.0, .y = 1.0, .z = 0.0, .w = 0.0 },
            Vec4(f32){ .x = 0.0, .y = 0.0, .z = 1.0, .w = 0.0 },
            Vec4(f32){ .x = 1.0, .y = 2.0, .z = 3.0, .w = 1.0 },
        } };
        const b = Mat4(f32){ .cols = [4]Vec4(f32){
            Vec4(f32){ .x = 2.0, .y = 0.0, .z = 0.0, .w = 0.0 },
            Vec4(f32){ .x = 0.0, .y = 2.0, .z = 0.0, .w = 0.0 },
            Vec4(f32){ .x = 0.0, .y = 0.0, .z = 2.0, .w = 0.0 },
            Vec4(f32){ .x = 0.0, .y = 0.0, .z = 0.0, .w = 1.0 },
        } };
        const r = a.Mat4MulMat4(b);
        try std.testing.expectApproxEqAbs(@as(f32, 2.0), r.cols[0].x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), r.cols[0].y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), r.cols[0].z, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), r.cols[0].w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), r.cols[1].x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 2.0), r.cols[1].y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), r.cols[1].z, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), r.cols[1].w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), r.cols[2].x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), r.cols[2].y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 2.0), r.cols[2].z, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), r.cols[2].w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 1.0), r.cols[3].x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 2.0), r.cols[3].y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 3.0), r.cols[3].z, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 1.0), r.cols[3].w, eps);
    }

    // case 2
    {
        const a = Mat4(f32){ .cols = [4]Vec4(f32){
            Vec4(f32){ .x = 1.0, .y = 0.0, .z = 0.0, .w = 0.0 },
            Vec4(f32){ .x = 0.0, .y = 1.0, .z = 0.0, .w = 0.0 },
            Vec4(f32){ .x = 0.0, .y = 0.0, .z = 1.0, .w = 0.0 },
            Vec4(f32){ .x = 0.0, .y = 0.0, .z = 0.0, .w = 1.0 },
        } };
        const b = Mat4(f32){ .cols = [4]Vec4(f32){
            Vec4(f32){ .x = 1.0, .y = 3.0, .z = 0.0, .w = 0.0 },
            Vec4(f32){ .x = 2.0, .y = 4.0, .z = 0.0, .w = 0.0 },
            Vec4(f32){ .x = 0.0, .y = 0.0, .z = 1.0, .w = 0.0 },
            Vec4(f32){ .x = 0.0, .y = 0.0, .z = 0.0, .w = 1.0 },
        } };
        const r = a.Mat4MulMat4(b);
        try std.testing.expectApproxEqAbs(@as(f32, 1.0), r.cols[0].x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 3.0), r.cols[0].y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), r.cols[0].z, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), r.cols[0].w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 2.0), r.cols[1].x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 4.0), r.cols[1].y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), r.cols[1].z, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), r.cols[1].w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), r.cols[2].x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), r.cols[2].y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 1.0), r.cols[2].z, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), r.cols[2].w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), r.cols[3].x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), r.cols[3].y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), r.cols[3].z, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 1.0), r.cols[3].w, eps);
    }

    // Inverse

    // inverse case 0
    {
        const m = Mat4(f32){ .cols = [4]Vec4(f32){
            Vec4(f32){ .x = 1.0, .y = 0.0, .z = 0.0, .w = 0.0 },
            Vec4(f32){ .x = 2.0, .y = 1.0, .z = 0.0, .w = 0.0 },
            Vec4(f32){ .x = 0.0, .y = 0.0, .z = 1.0, .w = 0.0 },
            Vec4(f32){ .x = 0.0, .y = 0.0, .z = 0.0, .w = 1.0 },
        } };
        const inv = m.Inverse();
        // verify m * inv = identity
        const identity = m.Mat4MulMat4(inv);
        try std.testing.expectApproxEqAbs(@as(f32, 1e+00), identity.cols[0].x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0e+00), identity.cols[0].y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0e+00), identity.cols[0].z, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0e+00), identity.cols[0].w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0e+00), identity.cols[1].x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 1e+00), identity.cols[1].y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0e+00), identity.cols[1].z, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0e+00), identity.cols[1].w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0e+00), identity.cols[2].x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0e+00), identity.cols[2].y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 1e+00), identity.cols[2].z, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0e+00), identity.cols[2].w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0e+00), identity.cols[3].x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0e+00), identity.cols[3].y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0e+00), identity.cols[3].z, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 1e+00), identity.cols[3].w, eps);
    }

    // inverse case 1
    {
        const m = Mat4(f32){ .cols = [4]Vec4(f32){
            Vec4(f32){ .x = 2.0, .y = 0.0, .z = 0.0, .w = 0.0 },
            Vec4(f32){ .x = 0.0, .y = 3.0, .z = 0.0, .w = 0.0 },
            Vec4(f32){ .x = 0.0, .y = 0.0, .z = 4.0, .w = 0.0 },
            Vec4(f32){ .x = 1.0, .y = 2.0, .z = 3.0, .w = 1.0 },
        } };
        const inv = m.Inverse();
        // verify m * inv = identity
        const identity = m.Mat4MulMat4(inv);
        try std.testing.expectApproxEqAbs(@as(f32, 1e+00), identity.cols[0].x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0e+00), identity.cols[0].y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0e+00), identity.cols[0].z, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0e+00), identity.cols[0].w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0e+00), identity.cols[1].x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 1e+00), identity.cols[1].y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0e+00), identity.cols[1].z, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0e+00), identity.cols[1].w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0e+00), identity.cols[2].x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0e+00), identity.cols[2].y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 1e+00), identity.cols[2].z, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0e+00), identity.cols[2].w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0e+00), identity.cols[3].x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0e+00), identity.cols[3].y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0e+00), identity.cols[3].z, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 1e+00), identity.cols[3].w, eps);
    }

    // inverse case 2
    {
        const m = Mat4(f32){ .cols = [4]Vec4(f32){
            Vec4(f32){ .x = 1.0, .y = 0.0, .z = 0.0, .w = 0.0 },
            Vec4(f32){ .x = 0.0, .y = 1.0, .z = 0.0, .w = 0.0 },
            Vec4(f32){ .x = 0.0, .y = 0.0, .z = 1.0, .w = 0.0 },
            Vec4(f32){ .x = 5.0, .y = 6.0, .z = 7.0, .w = 1.0 },
        } };
        const inv = m.Inverse();
        // verify m * inv = identity
        const identity = m.Mat4MulMat4(inv);
        try std.testing.expectApproxEqAbs(@as(f32, 1e+00), identity.cols[0].x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0e+00), identity.cols[0].y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0e+00), identity.cols[0].z, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0e+00), identity.cols[0].w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0e+00), identity.cols[1].x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 1e+00), identity.cols[1].y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0e+00), identity.cols[1].z, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0e+00), identity.cols[1].w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0e+00), identity.cols[2].x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0e+00), identity.cols[2].y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 1e+00), identity.cols[2].z, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0e+00), identity.cols[2].w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0e+00), identity.cols[3].x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0e+00), identity.cols[3].y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0e+00), identity.cols[3].z, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 1e+00), identity.cols[3].w, eps);
    }
}

test "quat" {
    const eps: f32 = 0.0001;

    // FromRadians
    {
        const v = Vec3(f32){ .x = 0.0, .y = 0.0, .z = 0.0 };
        const q = Quat(f32).FromRadians(v);
        try std.testing.expectApproxEqAbs(@as(f32, 1.0), q.w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), q.x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), q.y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), q.z, eps);
    }
    {
        const v = Vec3(f32){ .x = 1.5708, .y = 0.0, .z = 0.0 };
        const q = Quat(f32).FromRadians(v);
        try std.testing.expectApproxEqAbs(@as(f32, 0.707107), q.w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.707107), q.x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), q.y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), q.z, eps);
    }
    {
        const v = Vec3(f32){ .x = 0.0, .y = 1.5708, .z = 0.0 };
        const q = Quat(f32).FromRadians(v);
        try std.testing.expectApproxEqAbs(@as(f32, 0.707107), q.w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), q.x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.707107), q.y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), q.z, eps);
    }
    {
        const v = Vec3(f32){ .x = 0.0, .y = 0.0, .z = 1.5708 };
        const q = Quat(f32).FromRadians(v);
        try std.testing.expectApproxEqAbs(@as(f32, 0.707107), q.w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), q.x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), q.y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.707107), q.z, eps);
    }
    {
        const v = Vec3(f32){ .x = 0.785398, .y = 0.785398, .z = 0.785398 };
        const q = Quat(f32).FromRadians(v);
        try std.testing.expectApproxEqAbs(@as(f32, 0.732538), q.w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.46194), q.x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.191342), q.y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.46194), q.z, eps);
    }
    {
        const v = Vec3(f32){ .x = 0.523599, .y = 1.0472, .z = 0.785398 };
        const q = Quat(f32).FromRadians(v);
        try std.testing.expectApproxEqAbs(@as(f32, 0.723317), q.w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.391904), q.x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.360423), q.y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.43968), q.z, eps);
    }
    {
        const q1 = Quat(f32){ .w = 0.707107, .x = 0.707107, .y = 0.0, .z = 0.0 };
        const q2 = Quat(f32){ .w = 0.707107, .x = 0.0, .y = 0.707107, .z = 0.0 };
        const r = q1.MulQuat(q2);
        try std.testing.expectApproxEqAbs(@as(f32, 0.5), r.w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.5), r.x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.5), r.y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.5), r.z, eps);
    }
    {
        const q1 = Quat(f32){ .w = 0.707107, .x = 0.0, .y = 0.707107, .z = 0.0 };
        const q2 = Quat(f32){ .w = 0.707107, .x = 0.0, .y = 0.0, .z = 0.707107 };
        const r = q1.MulQuat(q2);
        try std.testing.expectApproxEqAbs(@as(f32, 0.5), r.w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.5), r.x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.5), r.y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.5), r.z, eps);
    }
    {
        const q1 = Quat(f32){ .w = 0.732538, .x = 0.46194, .y = 0.191342, .z = 0.46194 };
        const q2 = Quat(f32){ .w = 0.732538, .x = 0.46194, .y = 0.191342, .z = 0.46194 };
        const r = q1.MulQuat(q2);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0732233), r.w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.676777), r.x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.28033), r.y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.676777), r.z, eps);
    }
    {
        const q = Quat(f32){ .w = 0.707107, .x = 0.707107, .y = 0.0, .z = 0.0 };
        const c = q.Conjugate();
        try std.testing.expectApproxEqAbs(@as(f32, 0.707107), c.w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, -0.707107), c.x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, -0.0), c.y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, -0.0), c.z, eps);
    }
    {
        const q = Quat(f32){ .w = 0.707107, .x = 0.0, .y = 0.707107, .z = 0.0 };
        const c = q.Conjugate();
        try std.testing.expectApproxEqAbs(@as(f32, 0.707107), c.w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, -0.0), c.x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, -0.707107), c.y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, -0.0), c.z, eps);
    }
    {
        const q = Quat(f32){ .w = 0.707107, .x = 0.0, .y = 0.0, .z = 0.707107 };
        const c = q.Conjugate();
        try std.testing.expectApproxEqAbs(@as(f32, 0.707107), c.w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, -0.0), c.x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, -0.0), c.y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, -0.707107), c.z, eps);
    }
    {
        const q1 = Quat(f32){ .w = 0.707107, .x = 0.707107, .y = 0.0, .z = 0.0 };
        const q2 = Quat(f32){ .w = 0.707107, .x = 0.0, .y = 0.707107, .z = 0.0 };
        try std.testing.expectApproxEqAbs(@as(f32, 0.5), q1.Dot(q2), eps);
    }
    {
        const q1 = Quat(f32){ .w = 0.707107, .x = 0.0, .y = 0.707107, .z = 0.0 };
        const q2 = Quat(f32){ .w = 0.707107, .x = 0.0, .y = 0.0, .z = 0.707107 };
        try std.testing.expectApproxEqAbs(@as(f32, 0.5), q1.Dot(q2), eps);
    }
    {
        const q1 = Quat(f32){ .w = 0.732538, .x = 0.46194, .y = 0.191342, .z = 0.46194 };
        const q2 = Quat(f32){ .w = 0.732538, .x = 0.46194, .y = 0.191342, .z = 0.46194 };
        try std.testing.expectApproxEqAbs(@as(f32, 1.0), q1.Dot(q2), eps);
    }
    {
        const q = Quat(f32){ .w = 0.5, .x = 0.5, .y = 0.5, .z = 0.5 };
        const n = q.Normalized();
        try std.testing.expectApproxEqAbs(@as(f32, 0.5), n.w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.5), n.x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.5), n.y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.5), n.z, eps);
    }
    {
        const q = Quat(f32){ .w = 1.0, .x = 2.0, .y = 3.0, .z = 4.0 };
        const n = q.Normalized();
        try std.testing.expectApproxEqAbs(@as(f32, 0.182574), n.w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.365148), n.x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.547723), n.y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.730297), n.z, eps);
    }
    {
        const q = Quat(f32){ .w = 0.1, .x = 0.0, .y = 0.0, .z = 0.0 };
        const n = q.Normalized();
        try std.testing.expectApproxEqAbs(@as(f32, 1.0), n.w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), n.x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), n.y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), n.z, eps);
    }
    {
        const q1 = Quat(f32){ .w = 1.0, .x = 0.0, .y = 0.0, .z = 0.0 };
        const q2 = Quat(f32){ .w = 0.707107, .x = 0.707107, .y = 0.0, .z = 0.0 };
        const r = q1.Slerp(q2, 0.5);
        try std.testing.expectApproxEqAbs(@as(f32, 0.92388), r.w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.382683), r.x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), r.y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), r.z, eps);
    }
    {
        const q1 = Quat(f32){ .w = 0.707107, .x = 0.707107, .y = 0.0, .z = 0.0 };
        const q2 = Quat(f32){ .w = 0.707107, .x = 0.0, .y = 0.707107, .z = 0.0 };
        const r = q1.Slerp(q2, 0.5);
        try std.testing.expectApproxEqAbs(@as(f32, 0.816497), r.w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.408248), r.x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.408248), r.y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), r.z, eps);
    }
    {
        const q1 = Quat(f32){ .w = 0.707107, .x = 0.707107, .y = 0.0, .z = 0.0 };
        const q2 = Quat(f32){ .w = 0.707107, .x = 0.0, .y = 0.707107, .z = 0.0 };
        const r = q1.Slerp(q2, 0.25);
        try std.testing.expectApproxEqAbs(@as(f32, 0.788675), r.w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.57735), r.x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.211325), r.y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), r.z, eps);
    }
    {
        const axis = Vec3(f32){ .x = 1.0, .y = 0.0, .z = 0.0 };
        const q = Quat(f32).FromAxisAngle(axis, 1.5708);
        try std.testing.expectApproxEqAbs(@as(f32, 0.707107), q.w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.707107), q.x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), q.y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), q.z, eps);
    }
    {
        const axis = Vec3(f32){ .x = 0.0, .y = 1.0, .z = 0.0 };
        const q = Quat(f32).FromAxisAngle(axis, 1.5708);
        try std.testing.expectApproxEqAbs(@as(f32, 0.707107), q.w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), q.x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.707107), q.y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), q.z, eps);
    }
    {
        const axis = Vec3(f32){ .x = 0.0, .y = 0.0, .z = 1.0 };
        const q = Quat(f32).FromAxisAngle(axis, 3.14159);
        try std.testing.expectApproxEqAbs(@as(f32, 6.12303e-17), q.w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), q.x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), q.y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 1.0), q.z, eps);
    }
    {
        const axis = Vec3(f32){ .x = 0.57735, .y = 0.57735, .z = 0.57735 };
        const q = Quat(f32).FromAxisAngle(axis, 1.0472);
        try std.testing.expectApproxEqAbs(@as(f32, 0.866025), q.w, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.288675), q.x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.288675), q.y, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 0.288675), q.z, eps);
    }
}

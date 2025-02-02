const std = @import("std");
const math = std.math;

pub const Vec2f32 = @Vector(2, f32);
pub const Vec3f32 = @Vector(3, f32);
pub const Vec4f32 = @Vector(4, f32);
pub const Quatf32 = @Vector(4, f32); //indecies 0-3: {w, x, y, z}
pub const Mat2f32 = [2]Vec2f32;
pub const Mat3f32 = [3]Vec3f32;
pub const Mat4f32 = [4]Vec4f32;

pub fn Vec2(value_type: type) type {
    //note this is only temporary and when i have more time
    //i can make it more flexible but its too much right now
    std.debug.assert(value_type == f32);
    return extern struct {
        x: value_type,
        y: value_type,

        pub inline fn ToZigVector(self: @This()) Vec2f32 {
            return @bitCast(self);
        }
        pub inline fn PrintDebug(self: @This()) void {
            std.debug.print("x: {d:.2}, y: {d:.2}\n", .{ self.x, self.y });
        }
    };
}

pub fn Vec3(value_type: type) type {
    //note this is only temporary and when i have more time
    //i can make it more flexible but its too much right now
    std.debug.assert(value_type == f32);
    return extern struct {
        const Self = @This();
        x: value_type,
        y: value_type,
        z: value_type,

        pub inline fn ToZigVector(self: Self) Vec3f32 {
            return @bitCast(self);
        }
        pub inline fn PrintDebug(self: Self) void {
            std.debug.print("x: {d:.2}, y: {d:.2}, z: {d:.2}\n", .{ self.x, self.y, self.z });
        }
        pub fn Translate(self: Self) Mat4(f32) {
            //const m = Mat4Identity();
            //var result = m;
            //result.values[3] = Vec4(f32){.x = }
            //result[3] = (m[0] * @as(Vec4f32, @splat(v[0]))) + (m[1] * @as(Vec4f32, @splat(v[1]))) + (m[2] * @as(Vec4f32, @splat(v[2]))) + m[3];
            //return result;
            const factor0 = (Vec4(f32){ .x = 1.0, .y = 0.0, .z = 0.0, .w = 0.0 }).MulVec4(Vec4(f32){ .x = self.x, .y = self.x, .z = self.x, .w = self.x });
            const factor1 = (Vec4(f32){ .x = 1.0, .y = 0.0, .z = 0.0, .w = 0.0 }).MulVec4(Vec4(f32){ .x = self.y, .y = self.y, .z = self.y, .w = self.y });
            const factor2 = (Vec4(f32){ .x = 1.0, .y = 0.0, .z = 0.0, .w = 0.0 }).MulVec4(Vec4(f32){ .x = self.z, .y = self.z, .z = self.z, .w = self.z });
            const factor3 = Vec4(f32){ .x = 0.0, .y = 0.0, .z = 0.0, .w = 1.0 };

            var row = AddVec3(factor0, factor1);
            row = AddVec3(row, factor2);
            row = AddVec3(row, factor3);
            return Mat4(f32){ .values = [4]Self{
                Self{ .x = 1.0, .y = 0.0, .z = 0.0, .w = 0.0 },
                Self{ .x = 0.0, .y = 1.0, .z = 0.0, .w = 0.0 },
                Self{ .x = 0.0, .y = 0.0, .z = 1.0, .w = 0.0 },
                row,
            } };
        }
        pub fn Scale(v: Vec3f32) Mat4f32 {
            _ = v;
            //const m = InitMat4CompTime(1.0);
            //var result = m;
            //result[0] = m[0] * @as(Vec4f32, @splat(v[0]));
            //result[1] = m[1] * @as(Vec4f32, @splat(v[1]));
            //result[2] = m[2] * @as(Vec4f32, @splat(v[2]));
            //result[3] = m[3];
            //return result;
        }
        pub inline fn Splat4Vec(value: value_type) Vec4f32 {
            return @as(Vec4f32, @splat(value));
        }
        pub inline fn MulVec3(self: *Self, v: Self) Self {
            const self_zig = self.ToZigVector();
            const v_zig = v.ToZigVector();
            const result = self_zig * v_zig;
            return Self{ .x = result[0], .y = result[1], .z = result[2] };
        }
        pub inline fn AddVec3(self: *Self, v: Self) Self {
            const self_zig = self.ToZigVector();
            const v_zig = v.ToZigVector();
            const result = self_zig + v_zig;
            return Self{ .x = result[0], .y = result[1], .z = result[2] };
        }
    };
}

pub fn Vec4(value_type: type) type {
    //note this is only temporary and when i have more time
    //i can make it more flexible but its too much right now
    std.debug.assert(value_type == f32);
    return extern struct {
        const Self = @This();
        x: value_type,
        y: value_type,
        z: value_type,
        w: value_type,
        pub inline fn ToZigVector(self: Self) Vec4f32 {
            return @bitCast(self);
        }
        pub inline fn PrintDebug(self: Self) void {
            std.debug.print("x: {d:.2}, y: {d:.2}, z: {d:.2}, w: {d:.2}\n", .{ self.x, self.y, self.z, self.w });
        }
        pub inline fn MulVec4(self: *Self, v: Self) Self {
            const self_zig = self.ToZigVector();
            const v_zig = v.ToZigVector();
            const result = self_zig * v_zig;
            return Self{ .x = result[0], .y = result[1], .z = result[2], .w = result[3] };
        }
        pub inline fn AddVec4(self: *Self, v: Self) Self {
            const self_zig = self.ToZigVector();
            const v_zig = v.ToZigVector();
            const result = self_zig + v_zig;
            return Self{ .x = result[0], .y = result[1], .z = result[2], .w = result[3] };
        }
    };
}

pub fn Quat(value_type: type) type {
    //note this is only temporary and when i have more time
    //i can make it more flexible but its too much right now
    std.debug.assert(value_type == f32);
    return extern struct {
        const Self = @This();
        w: value_type,
        x: value_type,
        y: value_type,
        z: value_type,
        pub inline fn ToZigVector(self: Self) Quatf32 {
            return @bitCast(self);
        }
        pub inline fn PrintDebug(self: Self) void {
            std.debug.print("w: {d:.2}, x: {d:.2}, y: {d:.2}, z: {d:.2}\n", .{ self.w, self.x, self.y, self.z });
        }
        pub fn Normalize(self: Self) Self {
            const q = self.ToZigVector();
            const len = @sqrt(@reduce(.Add, q * q));
            if (len <= 0) {
                return Self{ .w = 1.0, .x = 0.0, .y = 0.0, .z = 0.0 };
            }
            const result = q / @as(Quatf32, @splat(len));
            return Self{
                .w = result[0],
                .x = result[1],
                .y = result[2],
                .z = result[3],
            };
        }
        pub fn ToMat4(self: Self) Mat4(f32) {
            const one: Vec3f32 = @splat(1.0);
            const two: Vec3f32 = @splat(2.0);
            const two2: Vec2f32 = @splat(2.0);

            const xx = self.x * self.x;
            const yy = self.y * self.y;
            const zz = self.z * self.z;
            const xy = self.x * self.y;
            const xz = self.x * self.z;
            const xw = self.x * self.w;
            const yz = self.y * self.z;
            const yw = self.y * self.w;
            const zw = self.z * self.w;

            const diag = one - (two * Vec3f32{ yy + zz, xx + zz, xx + yy });

            const r1 = two2 * Vec2f32{ xy + zw, xz - yw };
            const r2 = two2 * Vec2f32{ xy - zw, yz + xw };
            const r3 = two2 * Vec2f32{ xz + yw, yz - xw };

            return Mat4(f32){ .values = [4]Vec4(f32){
                Vec4(f32){ .x = diag[0], .y = r1[0], .z = r1[1], .w = 0.0 },
                Vec4(f32){ .x = r2[0], .y = diag[1], .z = r2[1], .w = 0.0 },
                Vec4(f32){ .x = r3[0], .y = r3[1], .z = diag[2], .w = 0.0 },
                Vec4(f32){ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 },
            } };
        }
    };
}

pub fn Mat2(value_type: type) type {
    //note this is only temporary and when i have more time
    //i can make it more flexible but its too much right now
    std.debug.assert(value_type == f32);
    return extern struct {
        values: [2]Vec2(value_type),
        pub inline fn ToZigMatrix(self: @This()) Mat2f32 {
            return @bitCast(self);
        }
        pub inline fn PrintDebug(self: @This()) void {
            for (self.values) |val| {
                val.PrintDebug();
            }
        }
    };
}

pub fn Mat3(value_type: type) type {
    //note this is only temporary and when i have more time
    //i can make it more flexible but its too much right now
    std.debug.assert(value_type == f32);
    return extern struct {
        values: [3]Vec3(value_type),
        pub inline fn ToZigMatrix(self: @This()) Mat3f32 {
            return @bitCast(self);
        }
        pub inline fn PrintDebug(self: @This()) void {
            for (self.values) |val| {
                val.PrintDebug();
            }
        }
    };
}

pub fn Mat4(value_type: type) type {
    //note this is only temporary and when i have more time
    //i can make it more flexible but its too much right now
    std.debug.assert(value_type == f32);
    return extern struct {
        values: [4]Vec4(value_type),
        pub inline fn ToZigMatrix(self: @This()) Mat4f32 {
            return @bitCast(self);
        }
        pub inline fn PrintDebug(self: @This()) void {
            for (self.values) |val| {
                val.PrintDebug();
            }
        }
        pub fn MulVec4(self: @This(), v: Vec4(f32)) Vec4(f32) {
            const vz = v.ToZigVector();
            const mov0: Vec4f32 = @splat(vz[0]);
            const mov1: Vec4f32 = @splat(vz[1]);
            const mov2: Vec4f32 = @splat(vz[2]);
            const mov3: Vec4f32 = @splat(vz[3]);

            const mul0 = self.values[0].ToZigVector() * mov0;
            const mul1 = self.values[1].ToZigVector() * mov1;
            const mul2 = self.values[2].ToZigVector() * mov2;
            const mul3 = self.values[3].ToZigVector() * mov3;

            const add0 = mul0 + mul1;
            const add1 = mul2 + mul3;

            return add0 + add1;
        }
        pub fn MulMat4(self: @This(), m2: Mat4(f32)) Mat4(f32) {
            const srca0 = self.values[0].ToZigVector();
            const srca1 = self.values[1].ToZigVector();
            const srca2 = self.values[2].ToZigVector();
            const srca3 = self.values[3].ToZigVector();

            const srcb0 = m2.values[0].ToZigVector();
            const srcb1 = m2.values[1].ToZigVector();
            const srcb2 = m2.values[2].ToZigVector();
            const srcb3 = m2.values[3].ToZigVector();

            const result0 = srca0 * @as(Vec4f32, @splat(srcb0[0])) +
                srca1 * @as(Vec4f32, @splat(srcb0[1])) +
                srca2 * @as(Vec4f32, @splat(srcb0[2])) +
                srca3 * @as(Vec4f32, @splat(srcb0[3]));
            const result1 = srca0 * @as(Vec4f32, @splat(srcb1[0])) +
                srca1 * @as(Vec4f32, @splat(srcb1[1])) +
                srca2 * @as(Vec4f32, @splat(srcb1[2])) +
                srca3 * @as(Vec4f32, @splat(srcb1[3]));
            const result2 = srca0 * @as(Vec4f32, @splat(srcb2[0])) +
                srca1 * @as(Vec4f32, @splat(srcb2[1])) +
                srca2 * @as(Vec4f32, @splat(srcb2[2])) +
                srca3 * @as(Vec4f32, @splat(srcb2[3]));
            const result3 = srca0 * @as(Vec4f32, @splat(srcb3[0])) +
                srca1 * @as(Vec4f32, @splat(srcb3[1])) +
                srca2 * @as(Vec4f32, @splat(srcb3[2])) +
                srca3 * @as(Vec4f32, @splat(srcb3[3]));

            return Mat4(f32){ .values = [4]Vec4(f32){
                ToStructVec4(result0),
                ToStructVec4(result1),
                ToStructVec4(result2),
                ToStructVec4(result3),
            } };
        }
    };
}

pub fn ToStructVec4(v: @Vector(4, f32)) Vec4(f32) {
    return @bitCast(v);
}

pub fn Mat4Identity() Mat4(f32) {
    return Mat4(f32){ .values = [4]Vec4(f32){
        Vec4(f32){ .x = 1.0, .y = 0.0, .z = 0.0, .w = 0.0 },
        Vec4(f32){ .x = 0.0, .y = 1.0, .z = 0.0, .w = 0.0 },
        Vec4(f32){ .x = 0.0, .y = 0.0, .z = 1.0, .w = 0.0 },
        Vec4(f32){ .x = 0.0, .y = 0.0, .z = 0.0, .w = 1.0 },
    } };
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
        Vec4f32{ 0.0, 1 / tanHalfFovy, 0.0, 0.0 },
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

const std = @import("std");
const math = std.math;

pub const Axis = enum { x, y, z };
pub fn Mat4Identity(comptime number_type: type) Mat4(number_type) {
    _ValidateNumberType(number_type);
    return Mat4(number_type){ .cols = .{
        Vec4(number_type){ .w = 1, .x = 0, .y = 0, .z = 0 },
        Vec4(number_type){ .w = 0, .x = 1, .y = 0, .z = 0 },
        Vec4(number_type){ .w = 0, .x = 0, .y = 1, .z = 0 },
        Vec4(number_type){ .w = 0, .x = 0, .y = 0, .z = 1 },
    } };
}

pub fn Vec2(comptime number_type: type) type {
    _ValidateNumberType(number_type);
    return packed struct {
        const Self = @This();
        const VectorT = @Vector(2, number_type);
        const ArrT = [2]number_type;

        x: number_type,
        y: number_type,

        pub fn Len(self: Self) number_type {
            _EnsureFloat(number_type);
            const v = self.ToVector();
            return @sqrt(@reduce(.Add, v * v));
        }

        pub fn InitFromVector(vec: VectorT) Self {
            return @bitCast(vec);
        }

        pub fn Dir(self: Self) Self {
            const len = self.Len();
            if (len <= 0) {
                return Self{ .x = 0, .y = 0 };
            } else {
                return Self{ .x = self.x / len, .y = self.y / len };
            }
        }

        pub fn Dot(self: Self, other: Self) number_type {
            return @reduce(.Add, self.ToVector() * other.ToVector());
        }

        pub fn Normalize(self: *Self) void {
            const v = self.ToVector();
            const len = @sqrt(@reduce(.Add, v * v));
            if (len <= 0) {
                self.x = 0;
                self.y = 0;
            } else {
                self.x /= len;
                self.y /= len;
            }
        }

        pub fn ProjectOn(self: Self, other: Self) Self {
            const num = self.Dot(other);
            const denom = other.Dot(other);
            if (denom <= 0) return Self{ .x = 0, .y = 0 };

            return other.MulScaler(num / denom);
        }

        pub fn RejectFrom(self: Self, other: Self) Self {
            return self.SubVec(self.ProjectOn(other));
        }

        pub fn DistanceSquared(self: Self, other: Self) number_type {
            const diff = self.SubVec(other);
            const v = diff.ToVector();
            return @reduce(.Add, v * v);
        }

        pub fn Distance(self: Self, other: Self) number_type {
            return @sqrt(self.DistanceSquared(other));
        }

        pub fn Lerp(self: Self, target: Self, t: number_type) Self {
            // Formula: self + (target - self) * t
            return self.AddVec(target.SubVec(self).MulScaler(t));
        }

        pub fn AddVec(self: Self, other: Self) Self {
            return @bitCast(self.ToVector() + other.ToVector());
        }

        pub fn SubVec(self: Self, other: Self) Self {
            return @bitCast(self.ToVector() - other.ToVector());
        }

        pub fn MulScaler(self: Self, scalar: number_type) Self {
            return @bitCast(self.ToVector() * @as(VectorT, @splat(scalar)));
        }

        pub fn ToVector(self: Self) VectorT {
            return @bitCast(self);
        }

        pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            try writer.print("{s} - x: {}, y: {},\n", .{ @typeName(Self), self.x, self.y });
        }

        //=================TESTS=========================

    };
}

pub fn Vec3(comptime number_type: type) type {
    return packed struct {
        const Self = @This();
        const VectorT = @Vector(3, number_type);
        const ArrT = [3]number_type;

        x: number_type,
        y: number_type,
        z: number_type,

        pub fn InitFromVector(vect: VectorT) Self {
            return @bitCast(vect);
        }

        pub fn ToVector(self: Self) VectorT {
            return @bitCast(self);
        }

        pub fn Cross(self: Self, other: Self) Self {
            return Self{
                .x = self.y * other.z - self.z * other.y,
                .y = self.z * other.x - self.x * other.z,
                .z = self.x * other.y - self.y * other.x,
            };
        }

        pub fn ToQuat(self: Self) Quat(number_type) {
            const v = self.ToVector();

            const c_vec = @cos(v * @as(VectorT, @splat(0.5)));
            const s_vec = @sin(v * @as(VectorT, @splat(0.5)));

            const c: ArrT = c_vec;
            const s: ArrT = s_vec;

            const cx = c[0];
            const cy = c[1];
            const cz = c[2];
            const sx = s[0];
            const sy = s[1];
            const sz = s[2];

            return Quat(number_type){
                .w = cx * cy * cz - sx * sy * sz,
                .x = sx * cy * cz + cx * sy * sz,
                .y = cx * sy * cz - sx * cy * sz,
                .z = cx * cy * sz + sx * sy * cz,
            };
        }

        pub fn Len(self: Self) number_type {
            _EnsureFloat(number_type);
            const v = self.ToVector();
            return @sqrt(@reduce(.Add, v * v));
        }

        pub fn Dir(self: Self) Self {
            const len = self.Len();
            if (len <= 0) {
                return Self{ .x = 0, .y = 0, .z = 0 };
            } else {
                return Self{ .x = self.x / len, .y = self.y / len, .z = self.z / len };
            }
        }

        pub fn Dot(self: Self, other: Self) number_type {
            return @reduce(.Add, self.ToVector() * other.ToVector());
        }

        pub fn Normalize(self: *Self) void {
            const v = self.ToVector();
            const len = @sqrt(@reduce(.Add, v * v));
            if (len <= 0) {
                self.x = 0;
                self.y = 0;
                self.z = 0;
            } else {
                self.x /= len;
                self.y /= len;
                self.z /= len;
            }
        }

        pub fn ProjectOn(self: Self, other: Self) Self {
            const num = self.Dot(other);
            const denom = other.Dot(other);
            if (denom <= 0) return Self{ .x = 0, .y = 0, .z = 0 };

            return other.MulScaler(num / denom);
        }

        pub fn RejectFrom(self: Self, other: Self) Self {
            return self.SubVec(self.ProjectOn(other));
        }

        pub fn DistanceSquared(self: Self, other: Self) number_type {
            const diff = self.SubVec(other);
            const v = diff.ToVector();
            return @reduce(.Add, v * v);
        }

        pub fn Distance(self: Self, other: Self) number_type {
            return @sqrt(self.DistanceSquared(other));
        }

        pub fn Lerp(self: Self, target: Self, t: number_type) Self {
            // Formula: self + (target - self) * t
            return self.AddVec(target.SubVec(self).MulScaler(t));
        }

        pub fn AddVec(self: Self, other: Self) Self {
            return @bitCast(self.ToVector() + other.ToVector());
        }

        pub fn SubVec(self: Self, other: Self) Self {
            return @bitCast(self.ToVector() - other.ToVector());
        }

        pub fn MulScaler(self: Self, scalar: number_type) Self {
            return @bitCast(self.ToVector() * @as(VectorT, @splat(scalar)));
        }
        pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            try writer.print("{s} - x: {}, y: {}, z: {}\n", .{ @typeName(Self), self.x, self.y, self.z });
        }
        pub fn QuatRotate(self: Self, quat: Quat(number_type)) Self {
            const quat_vect = Self{ .x = quat.x, .y = quat.y, .z = quat.z };

            const uv = quat_vect.Cross(self);
            const uuv = quat_vect.Cross(uv);

            const expanded_uv = @as(VectorT, @splat(2.0)) * (uv.ToVector() * @as(VectorT, @splat(quat.w)));
            const expanded_uuv = @as(VectorT, @splat(2.0)) * uuv.ToVector();

            const res = self.ToVector() + expanded_uv + expanded_uuv;

            return Self{ .x = res[0], .y = res[1], .z = res[2] };
        }
        pub fn InvQuatRotate(self: Self, quat: Quat(number_type)) Self {
            return self.QuatRotate(quat.Conjugate());
        }
    };
}

pub fn Vec4(comptime number_type: type) type {
    _ValidateNumberType(number_type);
    return packed struct {
        const Self = @This();
        const VectorT = @Vector(4, number_type);
        const ArrT = [4]number_type;

        x: number_type,
        y: number_type,
        z: number_type,
        w: number_type,

        pub fn InitFromVector(vect: VectorT) Self {
            return @bitCast(vect);
        }

        pub fn Len(self: Self) number_type {
            _EnsureFloat(number_type);
            const v = self.ToVector();
            return @sqrt(@reduce(.Add, v * v));
        }

        pub fn Dir(self: Self) Self {
            const len = self.Len();
            if (len <= 0) {
                return Self{ .x = 0, .y = 0, .z = 0, .w = 0 };
            } else {
                return Self{ .x = self.x / len, .y = self.y / len, .z = self.z / len, .w = self.w / len };
            }
        }

        pub fn Dot(self: Self, other: Self) number_type {
            return @reduce(.Add, self.ToVector() * other.ToVector());
        }

        pub fn Normalize(self: *Self) void {
            const len = self.Len();
            if (len <= 0) {
                self.x = 0;
                self.y = 0;
                self.z = 0;
                self.w = 0;
            } else {
                self.x /= len;
                self.y /= len;
                self.z /= len;
                self.w /= len;
            }
        }

        pub fn ProjectOn(self: Self, other: Self) Self {
            const num = self.Dot(other);
            const denom = other.Dot(other);
            if (denom <= 0) return Self{ .x = 0, .y = 0, .z = 0, .w = 0 };

            return other.MulScaler(num / denom);
        }

        pub fn RejectFrom(self: Self, other: Self) Self {
            return self.SubVec(self.ProjectOn(other));
        }

        pub fn DistanceSquared(self: Self, other: Self) number_type {
            const diff = self.SubVec(other);
            const v = diff.ToVector();
            return @reduce(.Add, v * v);
        }

        pub fn Distance(self: Self, other: Self) number_type {
            return @sqrt(self.DistanceSquared(other));
        }

        pub fn Lerp(self: Self, target: Self, t: number_type) Self {
            // Formula: self + (target - self) * t
            return self.AddVec(target.SubVec(self).MulScaler(t));
        }

        pub fn AddVec(self: Self, other: Self) Self {
            return @bitCast(self.ToVector() + other.ToVector());
        }

        pub fn SubVec(self: Self, other: Self) Self {
            return @bitCast(self.ToVector() - other.ToVector());
        }

        pub fn MulScaler(self: Self, scalar: number_type) Self {
            return Self.InitFromVector(self.ToVector() * @as(VectorT, @splat(scalar)));
        }

        pub fn ToVector(self: Self) VectorT {
            return @bitCast(self);
        }

        pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            try writer.print("{s} - x: {}, y: {}, z: {}, w: {}\n", .{ @typeName(Self), self.x, self.y, self.z, self.w });
        }
    };
}

pub fn Mat3(comptime number_type: type) type {
    _ValidateNumberType(number_type);
    return packed struct {
        const Self = @This();
        const Vec3T = Vec3(number_type);

        cols: [3]Vec3T,

        pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            for (0..3) |i| {
                try writer.print("{s}{d}: \n", .{ @typeName(Self), i });
                self.data[i].format(fmt, options, writer);
            }
        }
    };
}

pub fn Mat4(comptime number_type: type) type {
    _ValidateNumberType(number_type);
    return packed struct {
        const Self = @This();
        const Vec4T = Vec4(number_type);

        cols: [4]Vec4T,

        pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            for (0..4) |i| {
                try writer.print("{s}{d}: \n", .{ @typeName(Self), i });
                self.cols[i].format(fmt, options, writer);
            }
        }

        pub fn MulVec4(self: Self, vect: Vec4(number_type)) Vec4(number_type) {
            const mov0: Vec4T.VectorT = @splat(vect.x);
            const mov1: Vec4T.VectorT = @splat(vect.y);
            const mov2: Vec4T.VectorT = @splat(vect.z);
            const mov3: Vec4T.VectorT = @splat(vect.w);

            const mul0 = self.cols[0].ToVector() * mov0;
            const mul1 = self.cols[1].ToVector() * mov1;
            const mul2 = self.cols[2].ToVector() * mov2;
            const mul3 = self.cols[3].ToVector() * mov3;

            const res = mul0 + mul1 + mul2 + mul3;

            return Vec4T.InitFromVector(res);
        }

        pub fn Mat4MulMat4(self: Self, other: Self) Self {
            return .{ .cols = [4]Vec4T{
                self.MulVec4(other.cols[0]),
                self.MulVec4(other.cols[1]),
                self.MulVec4(other.cols[2]),
                self.MulVec4(other.cols[3]),
            } };
        }

        pub fn Inverse(self: Self) Self {
            const Coef00 = self.cols[2].z * self.cols[3].w - self.cols[3].z * self.cols[2].w;
            const Coef02 = self.cols[1].z * self.cols[3].w - self.cols[3].z * self.cols[1].w;
            const Coef03 = self.cols[1].z * self.cols[2].w - self.cols[2].z * self.cols[1].w;

            const Coef04 = self.cols[2].y * self.cols[3].w - self.cols[3].y * self.cols[2].w;
            const Coef06 = self.cols[1].y * self.cols[3].w - self.cols[3].y * self.cols[1].w;
            const Coef07 = self.cols[1].y * self.cols[2].w - self.cols[2].y * self.cols[1].w;

            const Coef08 = self.cols[2].y * self.cols[3].z - self.cols[3].y * self.cols[2].z;
            const Coef10 = self.cols[1].y * self.cols[3].z - self.cols[3].y * self.cols[1].z;
            const Coef11 = self.cols[1].y * self.cols[2].z - self.cols[2].y * self.cols[1].z;

            const Coef12 = self.cols[2].x * self.cols[3].w - self.cols[3].x * self.cols[2].w;
            const Coef14 = self.cols[1].x * self.cols[3].w - self.cols[3].x * self.cols[1].w;
            const Coef15 = self.cols[1].x * self.cols[2].w - self.cols[2].x * self.cols[1].w;

            const Coef16 = self.cols[2].x * self.cols[3].z - self.cols[3].x * self.cols[2].z;
            const Coef18 = self.cols[1].x * self.cols[3].z - self.cols[3].x * self.cols[1].z;
            const Coef19 = self.cols[1].x * self.cols[2].z - self.cols[2].x * self.cols[1].z;

            const Coef20 = self.cols[2].x * self.cols[3].y - self.cols[3].x * self.cols[2].y;
            const Coef22 = self.cols[1].x * self.cols[3].y - self.cols[3].x * self.cols[1].y;
            const Coef23 = self.cols[1].x * self.cols[2].y - self.cols[2].x * self.cols[1].y;

            const Fac0 = Vec4T.VectorT{ Coef00, Coef00, Coef02, Coef03 };
            const Fac1 = Vec4T.VectorT{ Coef04, Coef04, Coef06, Coef07 };
            const Fac2 = Vec4T.VectorT{ Coef08, Coef08, Coef10, Coef11 };
            const Fac3 = Vec4T.VectorT{ Coef12, Coef12, Coef14, Coef15 };
            const Fac4 = Vec4T.VectorT{ Coef16, Coef16, Coef18, Coef19 };
            const Fac5 = Vec4T.VectorT{ Coef20, Coef20, Coef22, Coef23 };

            const vec0 = Vec4T.VectorT{ self.cols[1].x, self.cols[0].x, self.cols[0].x, self.cols[0].x };
            const vec1 = Vec4T.VectorT{ self.cols[1].y, self.cols[0].y, self.cols[0].y, self.cols[0].y };
            const vec2 = Vec4T.VectorT{ self.cols[1].z, self.cols[0].z, self.cols[0].z, self.cols[0].z };
            const vec3 = Vec4T.VectorT{ self.cols[1].w, self.cols[0].w, self.cols[0].w, self.cols[0].w };

            const Inv0 = vec1 * Fac0 - vec2 * Fac1 + vec3 * Fac2;
            const Inv1 = vec0 * Fac0 - vec2 * Fac3 + vec3 * Fac4;
            const Inv2 = vec0 * Fac1 - vec1 * Fac3 + vec3 * Fac5;
            const Inv3 = vec0 * Fac2 - vec1 * Fac4 + vec2 * Fac5;

            const SignA = Vec4T.VectorT{ 1, -1, 1, -1 };
            const SignB = Vec4T.VectorT{ -1, 1, -1, 1 };

            var inverse: [4]Vec4T.VectorT = .{
                Inv0 * SignA,
                Inv1 * SignB,
                Inv2 * SignA,
                Inv3 * SignB,
            };

            const Col0 = Vec4T.VectorT{ inverse[0][0], inverse[1][0], inverse[2][0], inverse[3][0] };

            const Dot1 = self.cols[0].Dot(Vec4T.InitFromVector(Col0));

            inverse[0] /= @as(Vec4T.VectorT, @splat(Dot1));
            inverse[1] /= @as(Vec4T.VectorT, @splat(Dot1));
            inverse[2] /= @as(Vec4T.VectorT, @splat(Dot1));
            inverse[3] /= @as(Vec4T.VectorT, @splat(Dot1));

            return .{ .cols = [4]Vec4T{
                .{ .x = inverse[0][0], .y = inverse[0][1], .z = inverse[0][2], .w = inverse[0][3] },
                .{ .x = inverse[1][0], .y = inverse[1][1], .z = inverse[1][2], .w = inverse[1][3] },
                .{ .x = inverse[2][0], .y = inverse[2][1], .z = inverse[2][2], .w = inverse[2][3] },
                .{ .x = inverse[3][0], .y = inverse[3][1], .z = inverse[3][2], .w = inverse[3][3] },
            } };
        }
    };
}

pub fn Quat(comptime number_type: type) type {
    _ValidateNumberType(number_type);
    return packed struct {
        const Self = @This();
        const VectorT = @Vector(4, number_type);
        const ArrT = [4]number_type;

        w: number_type,
        x: number_type,
        y: number_type,
        z: number_type,

        pub fn InitFromAxisAngle(axis: Vec3(number_type), angle: number_type) Self {
            const half = angle * 0.5;
            const s = @sin(half);
            return Self{
                .w = @cos(half),
                .x = axis.x * s,
                .y = axis.y * s,
                .z = axis.z * s,
            };
        }

        pub fn Len(self: Self) number_type {
            _EnsureFloat(number_type);
            const q = self.ToVector();
            return @sqrt(@reduce(.Add, q * q));
        }

        pub fn Normalize(self: *Self) void {
            const len = self.Len();
            if (len <= 0) {
                self.w = 1;
                self.x = 0;
                self.y = 0;
                self.z = 0;
            } else {
                self.w /= len;
                self.x /= len;
                self.y /= len;
                self.z /= len;
            }
        }

        pub fn Normalized(self: Self) Self {
            const len = self.Len();
            if (len <= 0) return Self{ .w = 1, .x = 0, .y = 0, .z = 0 };
            const v = self.ToVector() / @as(VectorT, @splat(len));
            return @bitCast(v);
        }

        pub fn MulQuat(self: Self, other: Self) Self {
            return Self{
                .w = self.w * other.w - self.x * other.x - self.y * other.y - self.z * other.z,
                .x = self.w * other.x + self.x * other.w + self.y * other.z - self.z * other.y,
                .y = self.w * other.y + self.y * other.w + self.z * other.x - self.x * other.z,
                .z = self.w * other.z + self.z * other.w + self.x * other.y - self.y * other.x,
            };
        }

        pub fn ToMat4(self: Self) Mat4(number_type) {
            const one: @Vector(3, number_type) = @splat(1);
            const two3: @Vector(3, number_type) = @splat(2.0);
            const two2: @Vector(2, number_type) = @splat(2.0);

            const xx = self.x * self.x;
            const yy = self.y * self.y;
            const zz = self.z * self.z;
            const xy = self.x * self.y;
            const xz = self.x * self.z;
            const xw = self.x * self.w;
            const yz = self.y * self.z;
            const yw = self.y * self.w;
            const zw = self.z * self.w;

            const diag: [3]number_type = one - (two3 * @Vector(3, number_type){ yy + zz, xx + zz, xx + yy });

            const r1: [2]number_type = two2 * @Vector(2, number_type){ xy + zw, xz - yw };
            const r2: [2]number_type = two2 * @Vector(2, number_type){ xy - zw, yz + xw };
            const r3: [2]number_type = two2 * @Vector(2, number_type){ xz + yw, yz - xw };

            return Mat4(number_type){ .cols = [4]Vec4(number_type){
                Vec4(number_type){ .x = diag[0], .y = r2[0], .z = r3[0], .w = 0 },
                Vec4(number_type){ .x = r1[0], .y = diag[1], .z = r3[1], .w = 0 },
                Vec4(number_type){ .x = r1[1], .y = r2[1], .z = diag[2], .w = 0 },
                Vec4(number_type){ .x = 0, .y = 0, .z = 0, .w = 1 },
            } };
        }

        pub fn ToMat3(self: Self) Mat3(number_type) {
            const v = self.ToVector();
            const q2: ArrT = v * v;
            return Mat3(number_type){ .cols = [3]Vec3(number_type){
                Vec3(number_type){
                    .x = q2[0] + q2[1] - q2[2] - q2[3],
                    .y = 2 * (self.x * self.y + self.w * self.z),
                    .z = 2 * (self.x * self.z - self.w * self.y),
                },
                Vec3(number_type){
                    .x = 2 * (self.x * self.y - self.w * self.z),
                    .y = q2[0] - q2[1] + q2[2] - q2[3],
                    .z = 2 * (self.y * self.z + self.w * self.x),
                },
                Vec3(number_type){
                    .x = 2 * (self.x * self.z + self.w * self.y),
                    .y = 2 * (self.y * self.z - self.w * self.x),
                    .z = q2[0] - q2[1] - q2[2] + q2[3],
                },
            } };
        }

        pub fn Normal(self: Self, axis: Axis) Vec3(number_type) {
            return switch (axis) {
                .x => self.ToMat3().cols[0],
                .y => self.ToMat3().cols[1],
                .z => self.ToMat3().cols[2],
            };
        }

        pub fn ToVector(self: Self) VectorT {
            return @bitCast(self);
        }

        pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            try writer.print("{s} - w: {}, x: {}, y: {}, z: {}\n", .{ @typeName(Self), self.w, self.x, self.y, self.z });
        }
        pub fn ToDegrees(self: Self) Vec3(number_type) {
            const rad = VectorT{ self.GetPitch(), self.GetYaw(), self.GetRoll() };
            const to_deg = @as(VectorT, @splat(180.0 / math.pi));
            const res = rad * to_deg;
            return Vec3(number_type){ .x = res[0], .y = res[1], .z = res[2] };
        }
        pub fn GetPitch(self: Self) number_type {
            const y = 2.0 * (self.y * self.z + self.w * self.x);
            const x = 1.0 - 2.0 * (self.x * self.x + self.y * self.y);

            if (std.math.approxEqRel(number_type, x, 0.0, 0.0000001) and std.math.approxEqRel(number_type, y, 0.0, 0.0000001)) {
                return math.atan2(self.x, self.w) * 2;
            }
            return math.atan2(y, x);
        }

        pub fn GetYaw(self: Self) number_type {
            return math.asin(math.clamp(-2.0 * (self.x * self.z - self.w * self.y), -1.0, 1.0));
        }

        pub fn GetRoll(self: Self) number_type {
            const y = 2.0 * (self.x * self.y + self.w * self.z);
            const sqr = self.ToVector() * self.ToVector();
            const x = sqr[0] + sqr[1] - sqr[2] - sqr[3];

            if (std.math.approxEqRel(number_type, x, 0.0, 0.0000001) and std.math.approxEqRel(number_type, y, 0.0, 0.0000001)) {
                return 0.0;
            }
            return math.atan2(y, x);
        }
        pub fn Conjugate(self: Self) Self {
            return .{ .w = self.w, .x = -self.x, .y = -self.y, .z = -self.z };
        }
        pub fn FromRadians(vec: Vec3(number_type)) Self {
            const hp = vec.x * 0.5;
            const hy = vec.y * 0.5;
            const hr = vec.z * 0.5;

            const cp = @cos(hp);
            const sp = @sin(hp);
            const cy = @cos(hy);
            const sy = @sin(hy);
            const cr = @cos(hr);
            const sr = @sin(hr);

            return Self{
                .w = cr * cp * cy + sr * sp * sy,
                .x = sr * cp * cy - cr * sp * sy,
                .y = cr * sp * cy + sr * cp * sy,
                .z = cr * cp * sy - sr * sp * cy,
            };
        }
        pub fn FromDegrees(vect: Vec3(number_type)) Self {
            const to_rad = math.pi / 180.0;
            const rad = vect.ToVector() * to_rad;
            return Self.FromEuler(.{ .x = rad[0], .y = rad[1], .z = rad[2] });
        }

        pub fn Dot(self: Self, other: Self) number_type {
            const a = self.ToVector();
            const b = other.ToVector();
            return @reduce(.Add, a * b);
        }

        pub fn Slerp(self: Self, other: Self, t: number_type) Self {
            var dot = self.Dot(other);
            var other_adj = other;

            if (dot < 0.0) {
                other_adj = Self{ .w = -other.w, .x = -other.x, .y = -other.y, .z = -other.z };
                dot = -dot;
            }

            if (dot > 0.9995) {
                const a = self.ToVector();
                const b = other_adj.ToVector();
                const res = a + @as(VectorT, @splat(t)) * (b - a);
                const q: Self = @bitCast(res);
                return q.Normalized();
            }

            const theta = math.acos(dot);
            const sin_theta = @sin(theta);
            const scale_a = @sin((1.0 - t) * theta) / sin_theta;
            const scale_b = @sin(t * theta) / sin_theta;

            const a = self.ToVector();
            const b = other_adj.ToVector();
            const res = @as(VectorT, @splat(scale_a)) * a + @as(VectorT, @splat(scale_b)) * b;
            return @bitCast(res);
        }
    };
}

pub fn _ValidateNumberType(comptime number_type: type) void {
    const type_info = @typeInfo(number_type);
    if (type_info != .int and type_info != .comptime_int and type_info != .float and type_info != .comptime_float) {
        @compileError(@typeName(number_type) ++ "vector type must be an int/float type");
    }
}

pub fn _EnsureFloat(comptime number_type: type) void {
    const type_info = @typeInfo(number_type);
    if (type_info != .float and type_info != .comptime_float) {
        @compileError(@typeName(number_type) ++ "vector must be float");
    }
}

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
        test "Vec2.InitFromVector" {
            const vect1 = Vec2(f32).VectorT{ 3, 4 };
            const vect2 = Vec2(f32).VectorT{ 1, 0 };
            const vect3 = Vec2(f32).VectorT{ -2, 3 };
            const vect4 = Vec2(f32).VectorT{ 0.5, 0.5 };

            const to_vec1 = Vec2(f32).InitFromVector(vect1);
            const to_vec2 = Vec2(f32).InitFromVector(vect2);
            const to_vec3 = Vec2(f32).InitFromVector(vect3);
            const to_vec4 = Vec2(f32).InitFromVector(vect4);

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
        test "Vec2.MulScaler" {
            const expected_x = [4]f32{ 7.5, 2.5, -5.0, 1.25 };
            const expected_y = [4]f32{ 10.0, 0.0, 7.5, 1.25 };
            for (tests, expected_x, expected_y) |st, ex, ey| {
                const mul = st.a.MulScaler(2.5);
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
        test "Vec3.InitFromVector" {
            const vect1 = Vec3(f32).VectorT{ 3, 4, 0 };
            const vect2 = Vec3(f32).VectorT{ 1, 0, 0 };
            const vect3 = Vec3(f32).VectorT{ -2, 3, 1 };
            const vect4 = Vec3(f32).VectorT{ 0.5, 0.5, 0.5 };

            const to_vec1 = Vec3(f32).InitFromVector(vect1);
            const to_vec2 = Vec3(f32).InitFromVector(vect2);
            const to_vec3 = Vec3(f32).InitFromVector(vect3);
            const to_vec4 = Vec3(f32).InitFromVector(vect4);

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
        test "Vec3.MulScaler" {
            const expected_x = [4]f32{ 7.5, 2.5, -5.0, 1.25 };
            const expected_y = [4]f32{ 10.0, 0.0, 7.5, 1.25 };
            const expected_z = [4]f32{ 0.0, 0.0, 2.5, 1.25 };
            for (tests, expected_x, expected_y, expected_z) |st, ex, ey, ez| {
                const mul = st.a.MulScaler(2.5);
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
                const q = v.ToQuat();
                try std.testing.expectApproxEqAbs(@as(f32, 1.0), q.w, eps);
                try std.testing.expectApproxEqAbs(@as(f32, 0.0), q.x, eps);
                try std.testing.expectApproxEqAbs(@as(f32, 0.0), q.y, eps);
                try std.testing.expectApproxEqAbs(@as(f32, 0.0), q.z, eps);
            }
            // case 1: pitch=π/2, yaw=0, roll=0
            {
                const v = Vec3(f32){ .x = 1.5708, .y = 0.0, .z = 0.0 };
                const q = v.ToQuat();
                try std.testing.expectApproxEqAbs(@as(f32, 0.707107), q.w, eps);
                try std.testing.expectApproxEqAbs(@as(f32, 0.707107), q.x, eps);
                try std.testing.expectApproxEqAbs(@as(f32, 0.0), q.y, eps);
                try std.testing.expectApproxEqAbs(@as(f32, 0.0), q.z, eps);
            }
            // case 2: pitch=0, yaw=π/2, roll=0
            {
                const v = Vec3(f32){ .x = 0.0, .y = 1.5708, .z = 0.0 };
                const q = v.ToQuat();
                try std.testing.expectApproxEqAbs(@as(f32, 0.707107), q.w, eps);
                try std.testing.expectApproxEqAbs(@as(f32, 0.0), q.x, eps);
                try std.testing.expectApproxEqAbs(@as(f32, 0.707107), q.y, eps);
                try std.testing.expectApproxEqAbs(@as(f32, 0.0), q.z, eps);
            }
            // case 3: pitch=0, yaw=0, roll=π/2
            {
                const v = Vec3(f32){ .x = 0.0, .y = 0.0, .z = 1.5708 };
                const q = v.ToQuat();
                try std.testing.expectApproxEqAbs(@as(f32, 0.707107), q.w, eps);
                try std.testing.expectApproxEqAbs(@as(f32, 0.0), q.x, eps);
                try std.testing.expectApproxEqAbs(@as(f32, 0.0), q.y, eps);
                try std.testing.expectApproxEqAbs(@as(f32, 0.707107), q.z, eps);
            }
            // case 4: pitch=yaw=roll=π/4
            {
                const v = Vec3(f32){ .x = 0.785398, .y = 0.785398, .z = 0.785398 };
                const q = v.ToQuat();
                try std.testing.expectApproxEqAbs(@as(f32, 0.732538), q.w, eps);
                try std.testing.expectApproxEqAbs(@as(f32, 0.46194), q.x, eps);
                try std.testing.expectApproxEqAbs(@as(f32, 0.191342), q.y, eps);
                try std.testing.expectApproxEqAbs(@as(f32, 0.46194), q.z, eps);
            }
            // case 5: mixed
            {
                const v = Vec3(f32){ .x = 0.523599, .y = 1.0472, .z = 0.785398 };
                const q = v.ToQuat();
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
        test "Vec4.InitFromVector" {
            const vect1 = Vec4(f32).VectorT{ 1, 2, 3, 4 };
            const vect2 = Vec4(f32).VectorT{ 1, 0, 0, 0 };
            const vect3 = Vec4(f32).VectorT{ -1, 2, -3, 4 };
            const vect4 = Vec4(f32).VectorT{ 0.5, 0.5, 0.5, 0.5 };

            const to_vec1 = Vec4(f32).InitFromVector(vect1);
            const to_vec2 = Vec4(f32).InitFromVector(vect2);
            const to_vec3 = Vec4(f32).InitFromVector(vect3);
            const to_vec4 = Vec4(f32).InitFromVector(vect4);

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
        test "Vec4.MulScaler" {
            const expected_x = [4]f32{ 2.5, 2.5, -2.5, 1.25 };
            const expected_y = [4]f32{ 5.0, 0.0, 5.0, 1.25 };
            const expected_z = [4]f32{ 7.5, 0.0, -7.5, 1.25 };
            const expected_w = [4]f32{ 10.0, 0.0, 10.0, 1.25 };
            for (tests, expected_x, expected_y, expected_z, expected_w) |st, ex, ey, ez, ew| {
                const mul = st.a.MulScaler(2.5);
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

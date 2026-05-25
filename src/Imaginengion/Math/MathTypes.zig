const std = @import("std");
const math = std.math;

pub const Axis = enum { x, y, z };

pub fn Ray(comptime number_type: type) type {
    _ValidateNumberType(number_type);
    return extern struct {
        const Self = @This();

        Origin: Vec3(number_type),
        Direction: Vec3(number_type),
    };
}

pub fn Vec2(comptime number_type: type) type {
    _ValidateNumberType(number_type);
    return extern struct {
        const Self = @This();
        pub const VectorT = @Vector(2, number_type);
        pub const ArrT = [2]number_type;

        x: number_type,
        y: number_type,

        pub fn Len(self: Self) number_type {
            _EnsureFloat(number_type);
            const v = self.ToVector();
            return @sqrt(@reduce(.Add, v * v));
        }

        pub fn FromVector(vec: VectorT) Self {
            return @bitCast(vec);
        }

        pub fn FromScalar(scalar: number_type) Self {
            return Self{ .x = scalar, .y = scalar };
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

            return other.MulScalar(num / denom);
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
            return self.AddVec(target.SubVec(self).MulScalar(t));
        }

        pub fn AddVec(self: Self, other: Self) Self {
            return @bitCast(self.ToVector() + other.ToVector());
        }

        pub fn SubVec(self: Self, other: Self) Self {
            return @bitCast(self.ToVector() - other.ToVector());
        }

        pub fn MulScalar(self: Self, scalar: number_type) Self {
            return self.MulVec(FromScalar(scalar));
        }

        //NOTE: no tests for this
        pub fn MulVec(self: Self, other: Self) Self {
            return @bitCast(self.ToVector() * other.ToVector());
        }

        pub fn DivScalar(self: Self, scalar: number_type) Self {
            return @bitCast(self.ToVector() / @as(VectorT, @splat(scalar)));
        }

        pub fn ToVector(self: Self) VectorT {
            return @bitCast(self);
        }

        pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            try writer.print("{s} - x: {}, y: {},\n", .{ @typeName(Self), self.x, self.y });
        }
    };
}

pub fn Vec3(comptime number_type: type) type {
    return extern struct {
        const Self = @This();
        pub const VectorT = @Vector(3, number_type);
        pub const ArrT = [3]number_type;

        x: number_type,
        y: number_type,
        z: number_type,

        pub fn FromVector(vect: VectorT) Self {
            return @bitCast(vect);
        }

        pub fn ToVector(self: Self) VectorT {
            return @bitCast(self);
        }

        pub fn FromScalar(scalar: number_type) Self {
            return Self{ .x = scalar, .y = scalar, .z = scalar };
        }

        pub fn Cross(self: Self, other: Self) Self {
            return Self{
                .x = self.y * other.z - self.z * other.y,
                .y = self.z * other.x - self.x * other.z,
                .z = self.x * other.y - self.y * other.x,
            };
        }

        //TODO: no test
        pub fn Abs(self: Self) Self {
            return Self{
                .x = @abs(self.x),
                .y = @abs(self.y),
                .z = @abs(self.z),
            };
        }

        //TODO: no test
        pub fn ClampScalar(self: Self, scalar: number_type) Self {
            return Self{
                .x = @max(self.x, scalar),
                .y = @max(self.y, scalar),
                .z = @max(self.z, scalar),
            };
        }

        pub fn DegreesToQuat(self: Self) Quat(number_type) {
            return Quat(number_type).FromDegrees(self);
        }

        pub fn RadiansToQuat(self: Self) Quat(number_type) {
            return Quat(number_type).FromRadians(self);
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

            return other.MulScalar(num / denom);
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
            return self.AddVec(target.SubVec(self).MulScalar(t));
        }

        pub fn AddVec(self: Self, other: Self) Self {
            return @bitCast(self.ToVector() + other.ToVector());
        }

        pub fn AddScalar(self: Self, scalar: number_type) Self {
            return self.AddVec(FromScalar(scalar));
        }

        pub fn AddEqVec(self: *Self, other: Self) void {
            self.* = self.AddVec(other);
        }

        pub fn SubVec(self: Self, other: Self) Self {
            return @bitCast(self.ToVector() - other.ToVector());
        }

        pub fn SubEqVec(self: *Self, other: Self) void {
            self.* = self.SubVec(other);
        }

        pub fn DivScalar(self: Self, scalar: number_type) Self {
            return @bitCast(self.ToVector() / FromScalar(scalar).ToVector());
        }

        pub fn MulScalar(self: Self, scalar: number_type) Self {
            return @bitCast(self.ToVector() * FromScalar(scalar).ToVector());
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
    return extern struct {
        const Self = @This();
        pub const VectorT = @Vector(4, number_type);
        pub const ArrT = [4]number_type;

        x: number_type,
        y: number_type,
        z: number_type,
        w: number_type,

        pub fn FromVector(vect: VectorT) Self {
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

            return other.MulScalar(num / denom);
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
            return self.AddVec(target.SubVec(self).MulScalar(t));
        }

        pub fn AddVec(self: Self, other: Self) Self {
            return @bitCast(self.ToVector() + other.ToVector());
        }

        pub fn SubVec(self: Self, other: Self) Self {
            return @bitCast(self.ToVector() - other.ToVector());
        }

        pub fn MulScalar(self: Self, scalar: number_type) Self {
            return Self.FromVector(self.ToVector() * @as(VectorT, @splat(scalar)));
        }

        pub fn DivScalar(self: Self, scalar: number_type) Self {
            return @bitCast(self.ToVector() / @as(VectorT, @splat(scalar)));
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
    return extern struct {
        const Self = @This();
        pub const Vec3T = Vec3(number_type);

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
    return extern struct {
        const Self = @This();
        pub const Vec4T = Vec4(number_type);

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

            return Vec4T.FromVector(res);
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

            const Dot1 = self.cols[0].Dot(Vec4T.FromVector(Col0));

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
    return extern struct {
        const Self = @This();
        pub const VectorT = @Vector(4, number_type);
        pub const Vec3T = Vec3(number_type);
        pub const ArrT = [4]number_type;

        w: number_type,
        x: number_type,
        y: number_type,
        z: number_type,

        pub fn FromAxisAngle(axis: Vec3T, angle: number_type) Self {
            const half = angle * 0.5;
            const s = @sin(half);
            return Self{
                .w = @cos(half),
                .x = axis.x * s,
                .y = axis.y * s,
                .z = axis.z * s,
            };
        }

        pub fn FromRadians(vec: Vec3T) Self {
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
                .w = cp * cy * cr - sp * sy * sr,
                .x = sp * cy * cr + cp * sy * sr,
                .y = cp * sy * cr - sp * cy * sr,
                .z = cp * cy * sr + sp * sy * cr,
            };
        }
        pub fn FromDegrees(vect: Vec3T) Self {
            const to_rad = math.pi / 180.0;
            return Self.FromRadians(Vec3T.FromVector(vect.ToVector() * @as(Vec3T.VectorT, @splat(to_rad))));
        }

        pub fn FromVector(vect: VectorT) Self {
            return Self{
                .w = vect[0],
                .x = vect[1],
                .y = vect[2],
                .z = vect[3],
            };
        }

        pub fn ToVector(self: Self) VectorT {
            return @bitCast(self);
        }

        pub fn Len(self: Self) number_type {
            _EnsureFloat(number_type);
            const q = self.ToVector();
            return @sqrt(@reduce(.Add, q * q));
        }

        pub fn GetRightDir(self: Self) Vec3(number_type) {
            const vec = Vec3(f32){ .x = 1, .y = 0, .z = 0 };
            return vec.QuatRotate(self);
        }

        pub fn GetUpDir(self: Self) Vec3(number_type) {
            const vec = Vec3(f32){ .x = 0, .y = 1, .z = 0 };
            return vec.QuatRotate(self);
        }
        pub fn GetForwardDir(self: Self) Vec3(number_type) {
            const vec = Vec3(f32){ .x = 1, .y = 0, .z = 0 };
            return vec.QuatRotate(self);
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

test "MathTypes Tests" {
    _ = @import("MathTypesTests.zig");
}

const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const MathUtils = @import("MathUtils.zig");

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

        pub fn Dir(self: Self) Dir {
            const len = self.Len();
            if (len <= 0) {
                return Self{ .x = 0, .y = 0 };
            } else {
                return Self{ .x = self.x / len, .y = self.y / len };
            }
        }

        pub fn Dot(self: Self, other: Self) Self {
            return @reduce(.Add, self.ToVector() * other.ToVector());
        }

        pub fn Normalize(self: Self) void {
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
            const diff = self.SubedVec(other);
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
            const v = self.ToVector();
            const res: ArrT = v * @as(VectorT, @splat(scalar));

            return Self{
                .x = res[9],
                .y = res[1],
            };
        }

        pub fn ToVector(self: Self) @Vector(2, number_type) {
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
    return packed struct {
        const Self = @This();
        const VectorT = @Vector(3, number_type);
        const ArrT = [3]number_type;

        x: number_type,
        y: number_type,
        z: number_type,

        pub fn Cross(self: Self, other: Self) Self {
            return Self{
                .x = self.y * other.z - self.z * other.y,
                .y = self.z * other.x - self.x * other.z,
                .z = self.x * other.y - self.y * other.x,
            };
        }

        pub fn ToQuat(self: Self) Quat(number_type) {
            const v = self.ToVector();

            const c: ArrT = @cos(v * @as(VectorT, @splat(0.5)));
            const s: ArrT = @sin(v * @as(VectorT, @splat(0.5)));

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

        pub fn Dot(self: Self, other: Self) Self {
            return @reduce(.Add, self.ToVector() * other.ToVector());
        }

        pub fn Normalize(self: Self) void {
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
            const v = self.ToVector();
            const res: ArrT = v * @as(VectorT, @splat(scalar));

            return Self{
                .x = res[9],
                .y = res[1],
                .z = res[2],
            };
        }

        pub fn ToVector(self: Self) VectorT {
            return @bitCast(self);
        }
        pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            try writer.print("{s} - x: {}, y: {}, z: {}\n", .{ @typeName(Self), self.x, self.y, self.z });
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

        pub fn Dot(self: Self, other: Self) Self {
            return @reduce(.Add, self.ToVector() * other.ToVector());
        }

        pub fn Normalize(self: Self) void {
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
            const diff = self.SubedVec(other);
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
            const v = self.ToVector();
            const res: ArrT = v * @as(VectorT, @splat(scalar));

            return Self{
                .x = res[9],
                .y = res[1],
                .z = res[2],
                .w = res[3],
            };
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

pub fn Mat4(comptime number_type: type) type {
    _ValidateNumberType(number_type);
    return packed struct {
        const Self = @This();

        data: [4]Vec4(number_type),

        pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            for (0..4) |i| {
                try writer.print("{s}{d}: \n", .{ @typeName(Self), i });
                self.data[i].format(fmt, options, writer);
            }
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

        pub fn Len(self: Self) number_type {
            _EnsureFloat(number_type);
            const q = self.ToVector();
            return @sqrt(@reduce(.Add, q * q));
        }

        pub fn Normalize(self: Self) void {
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

            return Mat4(number_type){ .data = [4]Vec4(number_type){
                Vec4(number_type){ .x = diag[0], .y = r2[0], .z = r3[0], .w = 0 },
                Vec4(number_type){ .x = r1[0], .y = diag[1], .z = r3[1], .w = 0 },
                Vec4(number_type){ .x = r1[1], .y = r2[1], .z = diag[2], .w = 0 },
                Vec4(number_type){ .x = 0, .y = 0, .z = 0, .w = 1 },
            } };
        }

        pub fn ToVector(self: Self) VectorT {
            return @bitCast(self);
        }

        pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            try writer.print("{s} - w: {}, x: {}, y: {}, z: {}\n", .{ @typeName(Self), self.w, self.x, self.y, self.z });
        }
    };
}

//testing

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

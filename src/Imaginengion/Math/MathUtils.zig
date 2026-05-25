const std = @import("std");
const math = std.math;
const MathTypes = @import("MathTypes.zig");
const Mat4 = MathTypes.Mat4;
const Vec4 = MathTypes.Vec4;

pub fn Mat4Identity(comptime number_type: type) Mat4(number_type) {
    _ValidateNumberType(number_type);
    return Mat4(number_type){ .cols = .{
        Vec4(number_type){ .w = 1, .x = 0, .y = 0, .z = 0 },
        Vec4(number_type){ .w = 0, .x = 1, .y = 0, .z = 0 },
        Vec4(number_type){ .w = 0, .x = 0, .y = 1, .z = 0 },
        Vec4(number_type){ .w = 0, .x = 0, .y = 0, .z = 1 },
    } };
}

pub fn DegreesToRadians(degrees: anytype) @TypeOf(degrees) {
    const deg_t = @TypeOf(degrees);
    _ValidateNumberType(deg_t);
    _EnsureFloat(deg_t);
    return degrees * math.pi / 180.0;
}

pub fn RadiansToDegrees(radians: anytype) @TypeOf(radians) {
    const rad_t = @TypeOf(radians);
    _ValidateNumberType(rad_t);
    _EnsureFloat(rad_t);
    return radians * 180.0 / math.pi;
}

pub fn PerspectiveRHNO(fovy_radians: anytype, aspect: anytype, zNear: anytype, zFar: anytype) Mat4(@TypeOf(fovy_radians)) {
    _ValidateNumberType(@TypeOf(fovy_radians));
    _EnsureSame(.{ @TypeOf(fovy_radians), @TypeOf(aspect), @TypeOf(zNear), @TypeOf(zFar) });
    const number_type = @TypeOf(fovy_radians);

    const tanHalfFovy = math.tan(fovy_radians / 2);
    return .{
        .cols = [4]Vec4(number_type){
            Vec4(number_type){ .x = 1.0 / (aspect * tanHalfFovy), .y = 0.0, .z = 0.0, .w = 0.0 },
            Vec4(number_type){ .x = 0.0, .y = -1 / tanHalfFovy, .z = 0.0, .w = 0.0 },
            Vec4(number_type){ .x = 0.0, .y = 0.0, .z = -((zFar + zNear) / (zFar - zNear)), .w = -1.0 },
            Vec4(number_type){ .x = 0.0, .y = 0.0, .z = -((2.0 * zFar * zNear) / (zFar - zNear)), .w = 0.0 },
        },
    };
}

pub fn OrthographicRHNO(left: anytype, right: anytype, bottom: anytype, top: anytype, near: anytype, far: anytype) Mat4(@TypeOf(left)) {
    _ValidateNumberType(@TypeOf(left));
    _EnsureSame(.{ @TypeOf(left), @TypeOf(right), @TypeOf(bottom), @TypeOf(top), @TypeOf(near), @TypeOf(far) });
    const number_type = @TypeOf(left);

    const width = right - left;
    const height = top - bottom;
    const depth = far - near;

    return .{
        .cols = [4]Vec4(number_type){
            Vec4(number_type){ .x = 2.0 / width, .y = 0.0, .z = 0.0, .w = -(right + left) / width },
            Vec4(number_type){ .x = 0.0, .y = 2.0 / height, .z = 0.0, .w = -(top + bottom) / height },
            Vec4(number_type){ .x = 0.0, .y = 0.0, .z = -2.0 / depth, .w = -(far + near) / depth },
            Vec4(number_type){ .x = 0.0, .y = 0.0, .z = 0.0, .w = 1.0 },
        },
    };
}

pub fn Translate(x: anytype, y: anytype, z: anytype) Mat4(@TypeOf(x)) {
    _ValidateNumberType(@TypeOf(x));
    _EnsureSame(.{ @TypeOf(x), @TypeOf(y), @TypeOf(z) });
    const number_type = @TypeOf(x);

    var mat = Mat4Identity(number_type);

    const col0 = mat.cols[0].MulScaler(x);
    const col1 = mat.cols[1].MulScaler(y);
    const col2 = mat.cols[2].MulScaler(z);

    mat.cols[3] = col0.AddVec(col1).AddVec(col2).AddVec(math.cols[3]);
    return mat;
}

pub fn Scale(x: anytype, y: anytype, z: anytype) Mat4(@TypeOf(x)) {
    _ValidateNumberType(@TypeOf(x));
    _EnsureSame(.{ @TypeOf(x), @TypeOf(y), @TypeOf(z) });
    const number_type = @TypeOf(x);

    var mat = Mat4Identity(number_type);

    mat.cols[0] = mat.cols[0].MulScaler(x);
    mat.cols[1] = mat.cols[1].MulScaler(y);
    mat.cols[2] = mat.cols[2].MulScaler(z);

    return mat;
}

pub fn Sign(f: anytype) @TypeOf(f) {
    _ValidateNumberType(@TypeOf(f));
    _ValidateSignedType(@TypeOf(f));

    return if (f >= 0) 1 else -1;
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

pub fn _EnsureSame(comptime args: anytype) void {
    const args_type = @TypeOf(args);
    const info = @typeInfo(args_type);
    if (info != .@"struct" or !info.@"struct".is_tuple) {
        @compileError("Expected a tuple");
    }

    if (args.len == 0) return;

    const first = args[0];

    inline for (args) |item| {
        if (item != first) {
            @compileError("Types must be the same for args");
        }
    }
}

pub fn _ValidateSignedType(comptime number_type: type) void {
    const info = @typeInfo(number_type);
    if (info == .int and info.int.signedness == .unsigned) {
        @compileError(@typeName(number_type) ++ "Must be a type that can be negative");
    }
}

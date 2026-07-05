const std = @import("std");
const MathTypes = @import("MathTypes.zig");

const Vec2 = MathTypes.Vec2;
const Vec3 = MathTypes.Vec3;

/// Returns the reflected vector. 'Normal' must be normalized.
pub fn Reflect(vec: anytype, normal: @TypeOf(vec)) @TypeOf(vec) {
    _ValidateVec(@TypeOf(vec));
    return vec.SubVec(normal.MulScalar(2.0 * vec.Dot(normal)));
}

///Returns the projected vector. 'onto' does not need to be normalized
pub fn Project(vec: anytype, onto: @TypeOf(vec)) @TypeOf(vec) {
    _ValidateVec(@TypeOf(vec));

    const denom = onto.Dot(onto);

    if (denom == 0.0)
        return std.mem.zeroes(@TypeOf(vec));

    return onto.MulScalar(vec.Dot(onto) / denom);
}

///Returns the rejected vector. 'onto' does not need to be normalized
pub fn Reject(vec: anytype, onto: @TypeOf(vec)) @TypeOf(vec) {
    _ValidateVec(@TypeOf(vec));
    return vec.SubVec(Project(vec, onto));
}

fn _ValidateVec(vec_type: type) void {
    if (vec_type != Vec3(f32) or vec_type != Vec2(f32)) {
        @compileError(@typeName(vec_type) ++ "must be a vec2(f32) or vec3(f32) type");
    }
}

pub const Vec2f32 = extern struct {
    x: f32,
    y: f32,

    pub fn ToVector(self: Vec2f32) @Vector(2, f32) {
        return @bitCast(self);
    }

    pub fn ToColumnMajor(self: Vec2f32) [2][1]f32 {
        return @bitCast(self);
    }
};
pub const Vec3f32 = extern struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn ToVector(self: Vec2f32) @Vector(3, f32) {
        return @bitCast(self);
    }

    pub fn ToColumnMajor(self: Vec2f32) [3][1]f32 {
        return @bitCast(self);
    }
};
pub const Vec4f32 = extern struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,

    pub fn ToVector(self: Vec2f32) @Vector(4, f32) {
        return @bitCast(self);
    }

    pub fn ToColumnMajor(self: Vec2f32) [4][1]f32 {
        return @bitCast(self);
    }
};
pub const Mat2f32 = [2]Vec2f32;
pub const Mat3f32 = [3]Vec3f32;
pub const Mat4f32 = [4]Vec4f32;

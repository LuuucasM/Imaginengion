const MathTypes = @import("MathTypes.zig");
const Vec3 = MathTypes.Vec3;
const Quat = MathTypes.Quat;
const Vec2 = MathTypes.Vec2;
const Vec4 = MathTypes.Vec4;

const GlyphData = @import("../Renderer/Renderer2D.zig").GlyphData;
const QuadData = @import("../Renderer/Renderer2D.zig").QuadData;

pub const THICKNESS_2D: f32 = 0.001;

fn sdBox(point: Vec3(f32), half_extents: Vec3(f32)) f32 {
    const q = point.Abs().SubVec(half_extents);
    return q.ClampScalar(0).Len() + @min(@max(q.x, @max(q.y, q.z)), 0.0);
}

pub fn IMQuad(point: Vec3(f32), data: QuadData) f32 {
    return sdBox(
        point.SubVec(Vec3(f32).FromVector(data.Position)).InvQuatRotate(Quat(f32).FromVector(data.Rotation)),
        data.HalfExtents,
    );
}

pub fn IMGlyph(point: Vec3(f32), data: GlyphData) f32 {
    const p2: Vec3(f32) = .{
        .x = point.x - data.PlaneCenter[0],
        .y = point.y - data.PlaneCenter[1],
        .z = point.z,
    };
    return sdBox(p2, data.HalfExtents);
}

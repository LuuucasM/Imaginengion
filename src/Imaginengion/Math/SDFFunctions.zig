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

fn sdGlyph(point: Vec3(f32), data: GlyphData) f32 {
    const left = data.PlaneMin[0];
    const top = data.PlaneMin[1];
    const right = data.PlaneMax[0];
    const bottom = data.PlaneMax[1];

    const plane_size: Vec2(f32) = .{
        .x = (right - left) * data.Scale,
        .y = (top - bottom) * data.Scale,
    };
    const plane_center: Vec2(f32) = .{
        .x = (left + right) * 0.5 * data.Scale,
        .y = (top + bottom) * 0.5 * data.Scale,
    };

    const p2: Vec3(f32) = .{
        .x = point.x - plane_center.x,
        .y = point.y - plane_center.y,
        .z = point.z,
    };

    return sdBox(p2, .{ .x = plane_size.x * 0.5, .y = plane_size.y * 0.5, .z = THICKNESS_2D });
}

pub fn IMQuad(point: Vec3(f32), data: QuadData) f32 {
    return sdBox(
        point.SubVec(Vec3(f32).FromVector(data.Position)).InvQuatRotate(Quat(f32).FromVector(data.Rotation)),
        .{ .x = data.Scale[0] * 0.5, .y = data.Scale[1] * 0.5, .z = THICKNESS_2D },
    );
}

pub fn IMGlyph(point: Vec3(f32), data: GlyphData) f32 {
    return sdGlyph(
        point.SubVec(Vec3(f32).FromVector(data.Position)).InvQuatRotate(Quat(f32).FromVector(data.Rotation)),
        data,
    );
}

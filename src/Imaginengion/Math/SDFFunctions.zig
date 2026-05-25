const MathTypes = @import("MathTypes.zig");
const Vec3 = MathTypes.Vec3;
const Quat = MathTypes.Quat;
const Vec2 = MathTypes.Vec2;

const GlyphData = @import("../Renderer/Renderer2D.zig").GlyphData;

pub const THICKNESS_2D: f32 = 0.001;

fn sdBox(point: Vec3(f32), half_extents: Vec3(f32)) f32 {
    const q = point.Abs().SubVec(half_extents);
    return q.ClampScalar(0).Len() + @min(@max(q.x, @max(q.y, q.z)), 0.0);
}

fn sdGlyph(point: Vec3(f32), data: GlyphData) f32 {
    const left = data.PlaneMin.x;
    const top = data.PlaneMin.y;
    const right = data.PlaneMax.x;
    const bottom = data.PlaneMax.y;

    const plane_size: Vec2(f32) = .{
        .x = (right - left) * data.scale,
        .y = (top - bottom) * data.scale,
    };
    const plane_center: Vec2(f32) = .{
        .x = (left + right) * 0.5 * data.scale,
        .y = (top + bottom) * 0.5 * data.scale,
    };

    const p2: Vec3(f32) = .{
        .x = point[0] - plane_center[0],
        .y = point[1] - plane_center[1],
        .z = point[2],
    };

    return sdBox(p2, .{ .x = plane_size[0] * 0.5, .y = plane_size[1] * 0.5, .z = THICKNESS_2D });
}

pub fn IMQuad(point: Vec3(f32), translation: Vec3(f32), rotation: Quat(f32), scale: Vec3(f32)) f32 {
    return sdBox(
        point.SubVec(translation).InvQuatRotate(rotation),
        .{ scale[0] * 0.5, scale[1] * 0.5, THICKNESS_2D },
    );
}

pub fn IMGlyph(point: Vec3(f32), data: GlyphData) f32 {
    return sdGlyph(
        point.SubVec(data.Position).InvQuatRotate(data.Rotation),
        data,
    );
}

const MathTypes = @import("MathTypes.zig");
const Vec3 = MathTypes.Vec3;
const Quat = MathTypes.Quat;
const Vec2 = MathTypes.Vec2;
const Vec4 = MathTypes.Vec4;

const GlyphData = @import("../Renderer/Renderer2D.zig").GlyphData;
const QuadData = @import("../Renderer/Renderer2D.zig").QuadData;

const TextureManager = @import("../TextureManager/TextureManager.zig");

pub const THICKNESS_2D: f32 = 0.001;

fn sdBox(point: Vec3(f32), half_extents: Vec3(f32)) f32 {
    const q = point.Abs().SubVec(half_extents);
    return q.ClampScalar(0).Len() + @min(@max(q.x, @max(q.y, q.z)), 0.0);
}

fn uvBox(point: Vec3(f32), half_extents: Vec3(f32), texture_handle: u32) Vec3(f32) {
    const local_point_xy: Vec2(f32) = .{ .x = point.x, .y = point.y };
    const half_extents_xy: Vec2(f32) = .{ .x = half_extents.x, .y = half_extents.y };

    if (@abs(point.z - THICKNESS_2D) < THICKNESS_2D) { //check to ensure its the front face only
        const uv = local_point_xy.AddVec(half_extents_xy).DivVec(half_extents_xy.MulScalar(2.0));
        if (uv.x >= 0 and uv.x <= 1 and uv.y >= 0 and uv.y <= 1) {
            return TextureManager.GetTextureUV(texture_handle, uv);
        }
    }
    return .{ .x = -1, .y = -1 };
}

pub fn GetLocalPoint(point: Vec3(f32), position: Vec3(f32), rotation: Quat(f32)) Vec3(f32) {
    return point.SubVec(position).InvQuatRotate(rotation);
}

pub fn sdIMQuad(point: Vec3(f32), quad: QuadData) f32 {
    return sdBox(
        GetLocalPoint(point, .FromVector(quad.Position), .FromVector(quad.Rotation)),
        .FromVector(quad.HalfExtents),
    );
}

pub fn sdIMGlyph(point: Vec3(f32), glyph: GlyphData) f32 {
    const local_point = GetLocalPoint(point, .FromVector(glyph.Position), .FromVector(glyph.Rotation));

    const p2: Vec3(f32) = .{
        .x = local_point.x - glyph.PlaneCenter[0],
        .y = local_point.y - glyph.PlaneCenter[1],
        .z = local_point.z,
    };

    return sdBox(p2, .FromVector(glyph.HalfExtents));
}

pub fn uvIMQuad(point: Vec3(f32), quad: QuadData) Vec3(f32) {
    return uvBox(GetLocalPoint(point, .FromVector(quad.Position), .FromVector(quad.Rotation)), .FromVector(quad.HalfExtents), quad.ShadingHandle);
}

pub fn uvIMGlyph(point: Vec3(f32), glyph: GlyphData) Vec3(f32) {
    const local_point = GetLocalPoint(point, .FromVector(glyph.Position), .FromVector(glyph.Rotation));

    const p2: Vec3(f32) = .{
        .x = local_point.x - glyph.PlaneCenter[0],
        .y = local_point.y - glyph.PlaneCenter[1],
        .z = local_point.z,
    };

    return uvBox(p2, .FromVector(glyph.HalfExtents));
}

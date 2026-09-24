const MathTypes = @import("MathTypes.zig");
const Vec3 = MathTypes.Vec3;
const Quat = MathTypes.Quat;
const Vec2 = MathTypes.Vec2;
const Vec4 = MathTypes.Vec4;

const GlyphData = @import("../Renderer/Renderer2D.zig").GlyphData;
const QuadData = @import("../Renderer/Renderer2D.zig").QuadData;
const SurfShadingData = @import("../Renderer/Renderer.zig").SurfShadingData;

const TextureManager = @import("../TextureManager/TextureManager.zig");

pub const THICKNESS_2D: f32 = 0.001;

fn sdBox(point: Vec3(f32), half_extents: Vec3(f32)) f32 {
    const q = point.Abs().SubVec(half_extents);
    return q.ClampScalar(0).Len() + @min(@max(q.x, @max(q.y, q.z)), 0.0);
}

/// Where on the box's front face a point is, from (0, 0) bottom-left to (1, 1) top-right, or (-1, -1)
/// if it is off the front face.
fn LocalUVBox(point: Vec3(f32), half_extents: Vec3(f32)) Vec2(f32) {
    const local_point_xy: Vec2(f32) = .{ .x = point.x, .y = point.y };
    const half_extents_xy: Vec2(f32) = .{ .x = half_extents.x, .y = half_extents.y };

    //front face only: the marcher stops anywhere within its distance-scaled epsilon of the surface,
    //so this can't be a tight band around z = THICKNESS_2D or oblique/distant hits lose their UV
    if (point.z > 0.0) {
        const uv = local_point_xy.AddVec(half_extents_xy).DivVec(half_extents_xy.MulScalar(2.0));
        if (uv.x >= 0 and uv.x <= 1 and uv.y >= 0 and uv.y <= 1) {
            return uv;
        }
    }
    return .{ .x = -1, .y = -1 };
}

fn uvBox(point: Vec3(f32), half_extents: Vec3(f32), texture_handle: u32, tex_width: u32, tex_height: u32) Vec3(f32) {
    const uv = LocalUVBox(point, half_extents);
    if (uv.x < 0) return .{ .x = -1, .y = -1, .z = -1 };
    return TextureManager.GetTextureUV(texture_handle, uv, tex_width, tex_height);
}

fn GlyphLocalPoint(point: Vec3(f32), glyph: GlyphData) Vec3(f32) {
    const local_point = GetLocalPoint(point, .FromVector(glyph.Position), .FromVector(glyph.Rotation));
    return .{
        .x = local_point.x - glyph.PlaneCenter[0],
        .y = local_point.y - glyph.PlaneCenter[1],
        .z = local_point.z,
    };
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
    return sdBox(GlyphLocalPoint(point, glyph), .FromVector(glyph.HalfExtents));
}

pub fn uvIMQuad(point: Vec3(f32), quad: QuadData, texture_handle: u32, tex_width: u32, tex_height: u32) Vec3(f32) {
    return uvBox(
        GetLocalPoint(point, .FromVector(quad.Position), .FromVector(quad.Rotation)),
        .FromVector(quad.HalfExtents),
        texture_handle,
        tex_width,
        tex_height,
    );
}

/// Where on the glyph box's front face a point is, (0, 0) bottom-left to (1, 1) top-right, or (-1, -1)
/// off it. This is what GetMSD and TextureUV take, not a texture manager UV.
pub fn localUvIMGlyph(point: Vec3(f32), glyph: GlyphData) Vec2(f32) {
    return LocalUVBox(GlyphLocalPoint(point, glyph), .FromVector(glyph.HalfExtents));
}

/// A 0 to 1 position within a texture, as the texture manager's UV for that texture's slot.
pub fn TextureUV(texture_handle: u32, local_uv: Vec2(f32), tex_width: u32, tex_height: u32) Vec3(f32) {
    return TextureManager.GetTextureUV(texture_handle, local_uv, tex_width, tex_height);
}

/// `glyph_uv` is where in the glyph's box, from localUvIMGlyph. TextureUV0/1 are the glyph's
/// bottom-left and top-right in the atlas: textures load flipped so v runs bottom up, the same as
/// the font json's yOrigin bottom, and the same as glyph_uv.
pub fn GetMSD(glyph_uv: Vec2(f32), atlas_shading_data: SurfShadingData, textures_array: anytype, sample_sampler: anytype) f32 {
    //uv0 + (uv1 - uv0) * t. multiplying after the add instead gives uv1 * t, which samples everything
    //from the atlas corner to the glyph and paints a patch of other glyphs into this one's box
    const atlas_uv0 = Vec2(f32).FromArray(atlas_shading_data.TextureUV0);
    const raw_uv: Vec2(f32) = atlas_uv0.AddVec(Vec2(f32).FromArray(atlas_shading_data.TextureUV1).SubVec(atlas_uv0).MulVec(glyph_uv));
    const sample_uv = TextureManager.GetTextureUV(atlas_shading_data.Texturehandle, raw_uv, atlas_shading_data.TextureWidth, atlas_shading_data.TextureHeight);
    const msd = sample_sampler(textures_array, sample_uv.ToVector(), 0.0);
    return Median(msd[0], msd[1], msd[2]);
}

fn Median(a: f32, b: f32, c: f32) f32 {
    return @max(@min(a, b), @min(@max(a, b), c));
}

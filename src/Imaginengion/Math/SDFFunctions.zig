const MathTypes = @import("MathTypes.zig");
const Vec3 = MathTypes.Vec3;
const Quat = MathTypes.Quat;
const Vec2 = MathTypes.Vec2;
const Vec4 = MathTypes.Vec4;

const ShapeData = @import("../Renderer/Renderer2D.zig").ShapeData;
const ClipData = @import("../Renderer/Renderer2D.zig").ClipData;
pub const NO_CLIP = @import("../Renderer/Renderer2D.zig").NO_CLIP;
const SurfShadingData = @import("../Renderer/Renderer.zig").SurfShadingData;

const TextureManager = @import("../TextureManager/TextureManager.zig");

const RayIntersect = @import("RayIntersect.zig");
const HitInfo = RayIntersect.HitInfo;
const Ray = @import("CameraRay.zig").Ray;

pub const THICKNESS_2D: f32 = 0.001;

/// A sphere of `radius` around the origin
pub fn sdSphere(point: Vec3(f32), radius: f32) f32 {
    return point.Len() - radius;
}

/// The gradient of sdSphere: straight out from the center. At the center itself every direction is as
/// good as any other, so it picks +x
pub fn gradSphere(point: Vec3(f32)) Vec3(f32) {
    const length = point.Len();
    if (length <= 0.00001) return .{ .x = 1.0, .y = 0.0, .z = 0.0 };
    return point.DivScalar(length);
}

/// A box of `half_extents` around the origin
pub fn sdBox(point: Vec3(f32), half_extents: Vec3(f32)) f32 {
    const q = point.Abs().SubVec(half_extents);
    return q.ClampScalar(0).Len() + @min(@max(q.x, @max(q.y, q.z)), 0.0);
}

/// The gradient of sdBox, which is the surface normal at a hit, worked out directly rather than by
/// sampling the distance around the point (iq's sdgBox with no rounding).
pub fn gradBox(point: Vec3(f32), half_extents: Vec3(f32)) Vec3(f32) {
    const w = point.Abs().SubVec(half_extents);
    const g = @max(w.x, @max(w.y, w.z));

    //outside: toward the nearest point on the box, which blends faces around edges and corners.
    //inside: straight out of the nearest face, g > 0 above guarantees q is not zero
    const grad = if (g > 0.0) w.ClampScalar(0).Dir() else (Vec3(f32){
        .x = if (w.x == g) 1.0 else 0.0,
        .y = if (w.y == g) 1.0 else 0.0,
        .z = if (w.z == g) 1.0 else 0.0,
    }).Dir();

    //both of the above are for the positive octant, mirror back into the point's one
    return .{
        .x = if (point.x < 0.0) -grad.x else grad.x,
        .y = if (point.y < 0.0) -grad.y else grad.y,
        .z = if (point.z < 0.0) -grad.z else grad.z,
    };
}

/// iq's opRound: pushes a shape's surface out by `radius`, which rounds its edges and corners. It takes
/// the primitive's distance rather than the primitive, so it goes around any sd function.
pub fn opRound(distance: f32, radius: f32) f32 {
    return distance - radius;
}

/// A box with its edges and corners rounded off by `radius`. The rounding cuts into `half_extents`
/// rather than growing past it, so radius can be at most the smallest half extent.
pub fn sdRoundedBox(point: Vec3(f32), half_extents: Vec3(f32), radius: f32) f32 {
    return opRound(sdBox(point, half_extents.SubVec(.FromScalar(radius))), radius);
}

/// Normal of sdRoundedBox (iq's roundedboxNormal): straight out from the nearest point on the box the
/// rounding is swept around.
pub fn normalRoundedBox(point: Vec3(f32), half_extents: Vec3(f32), radius: f32) Vec3(f32) {
    return gradBox(point, half_extents.SubVec(.FromScalar(radius)));
}

/// The radius of whichever corner's quarter `point` is in. `radii` is in iq's order: x top right,
/// y bottom right, z top left, w bottom left.
fn CornerRadius(point: Vec2(f32), radii: Vec4(f32)) f32 {
    if (point.x > 0.0) {
        return if (point.y > 0.0) radii.x else radii.y;
    }
    return if (point.y > 0.0) radii.z else radii.w;
}

/// A 2D box with each corner rounded off by its own radius from `radii` (x top right, y bottom right,
/// z top left, w bottom left, iq's order). Pass the same radius four times to round them all alike.
/// Like sdRoundedBox, the rounding cuts into `half_extents`, so each radius can be at most the smaller half extent.
pub fn sdRoundedBox2D(point: Vec2(f32), half_extents: Vec2(f32), radii: Vec4(f32)) f32 {
    const r = CornerRadius(point, radii);
    const qx = @abs(point.x) - half_extents.x + r;
    const qy = @abs(point.y) - half_extents.y + r;
    const outside = (Vec2(f32){ .x = @max(qx, 0.0), .y = @max(qy, 0.0) }).Len();
    return opRound(@min(@max(qx, qy), 0.0) + outside, r);
}

/// Normal of sdRoundedBox2D, the 2D version of gradBox around the corner's inner box.
pub fn normalRoundedBox2D(point: Vec2(f32), half_extents: Vec2(f32), radii: Vec4(f32)) Vec2(f32) {
    const r = CornerRadius(point, radii);
    const wx = @abs(point.x) - half_extents.x + r;
    const wy = @abs(point.y) - half_extents.y + r;
    const g = @max(wx, wy);

    const grad = if (g > 0.0) (Vec2(f32){ .x = @max(wx, 0.0), .y = @max(wy, 0.0) }).Dir() else (Vec2(f32){
        .x = if (wx == g) 1.0 else 0.0,
        .y = if (wy == g) 1.0 else 0.0,
    }).Dir();

    return .{
        .x = if (point.x < 0.0) -grad.x else grad.x,
        .y = if (point.y < 0.0) -grad.y else grad.y,
    };
}

/// iq's opExtrusion: turns a 2D shape in the xy plane into a 3D slab of it `half_thickness` either side of
/// z = 0. Takes the 2D distance at point.xy rather than the shape, the same as opRound. Round in 2D first,
/// then extrude, for a plate with rounded corners and a thickness the rounding doesn't limit.
pub fn opExtrusion(point: Vec3(f32), distance_2d: f32, half_thickness: f32) f32 {
    const wz = @abs(point.z) - half_thickness;
    const outside = (Vec2(f32){ .x = @max(distance_2d, 0.0), .y = @max(wz, 0.0) }).Len();
    return @min(@max(distance_2d, wz), 0.0) + outside;
}

/// Normal of opExtrusion, from the 2D shape's distance and normal at point.xy.
pub fn normalExtrusion(point: Vec3(f32), distance_2d: f32, normal_2d: Vec2(f32), half_thickness: f32) Vec3(f32) {
    const wz = @abs(point.z) - half_thickness;
    const z_sign: f32 = if (point.z < 0.0) -1.0 else 1.0;

    //past both the side and the front/back is round the edge between them, which blends the two
    if (distance_2d > 0.0 and wz > 0.0) {
        return (Vec3(f32){ .x = normal_2d.x * distance_2d, .y = normal_2d.y * distance_2d, .z = z_sign * wz }).Dir();
    }
    //otherwise whichever is nearer, the same as the max() in opExtrusion
    if (distance_2d > wz) return .{ .x = normal_2d.x, .y = normal_2d.y, .z = 0.0 };
    return .{ .x = 0.0, .y = 0.0, .z = z_sign };
}

pub fn GetLocalPoint(point: Vec3(f32), position: Vec3(f32), rotation: Quat(f32)) Vec3(f32) {
    return point.SubVec(position).InvQuatRotate(rotation);
}

/// A quad is a thin plate: its 2D rounded box extruded to its thickness. Square corners (radii of 0) make it
/// exactly the plain box. Its corner radii are its Params
pub fn sdIMQuad(point: Vec3(f32), quad: ShapeData) f32 {
    const local_point = GetLocalPoint(point, .FromVector(quad.Position), .FromVector(quad.Rotation));
    const half_extents: Vec3(f32) = .FromVector(quad.Size);
    const distance_2d = sdRoundedBox2D(
        .{ .x = local_point.x, .y = local_point.y },
        .{ .x = half_extents.x, .y = half_extents.y },
        .FromVector(quad.Params),
    );
    return opExtrusion(local_point, distance_2d, half_extents.z);
}

/// Whether a point on the quad is in its border band: within border_width (its ShapeSurface's) of its (rounded) edge
pub fn InIMQuadBorder(point: Vec3(f32), quad: ShapeData, border_width: f32) bool {
    if (border_width <= 0) return false;
    const local_point = GetLocalPoint(point, .FromVector(quad.Position), .FromVector(quad.Rotation));
    const half_extents: Vec3(f32) = .FromVector(quad.Size);
    const distance_2d = sdRoundedBox2D(
        .{ .x = local_point.x, .y = local_point.y },
        .{ .x = half_extents.x, .y = half_extents.y },
        .FromVector(quad.Params),
    );
    return distance_2d > -border_width;
}

/// iq's opIntersection: inside where both shapes are, so the distance to it is the further of the two
pub fn opIntersection(distance_a: f32, distance_b: f32) f32 {
    return @max(distance_a, distance_b);
}

/// A clip region (ClipComponent): its rectangle in its own plane, running on through depth either way, so the cut
/// is the same for everything in front of it or behind it. Inside is negative
pub fn sdClipPrism(point: Vec3(f32), position: Vec3(f32), rotation: Quat(f32), half_extents: Vec2(f32)) f32 {
    const local_point = GetLocalPoint(point, position, rotation);
    return sdRoundedBox2D(.{ .x = local_point.x, .y = local_point.y }, half_extents, .{ .x = 0, .y = 0, .z = 0, .w = 0 });
}

pub fn sdIMClip(point: Vec3(f32), clip: ClipData) f32 {
    return sdClipPrism(point, .FromVector(clip.Position), .FromVector(clip.Rotation), .{ .x = clip.HalfExtents[0], .y = clip.HalfExtents[1] });
}

/// Whether a point on a shape is inside the clip region it is cut to
pub fn InIMClip(point: Vec3(f32), clip: ClipData) bool {
    return sdIMClip(point, clip) <= 0;
}

/// A texture UV that means "no texture, just the surface's color", for surfaces like a border that are a
/// solid color. A real UV's layer is never negative
pub const UNTEXTURED_UV: Vec3(f32) = .{ .x = 0, .y = 0, .z = -2 };

pub fn sdIMGlyph(point: Vec3(f32), glyph: ShapeData) f32 {
    return sdBox(GetLocalPoint(point, .FromVector(glyph.Position), .FromVector(glyph.Rotation)), .FromVector(glyph.Size));
}

/// The ray against the quad's box: where it hits, which face, and where on it.
pub fn rayIMQuad(ray: Ray, quad: ShapeData) HitInfo {
    return RayIntersect.RayRoundedBox2D(ray, .FromVector(quad.Position), .FromVector(quad.Rotation), .FromVector(quad.Size), .FromVector(quad.Params));
}

/// The ray against the glyph's box, centered on its Position.
/// UV is where in the glyph's box, which is what GetMSD and TextureUV take, not a texture manager UV.
pub fn rayIMGlyph(ray: Ray, glyph: ShapeData) HitInfo {
    return RayIntersect.RayBox(ray, .FromVector(glyph.Position), .FromVector(glyph.Rotation), .FromVector(glyph.Size));
}

/// A 0 to 1 position within a texture, as the texture manager's UV for that texture's slot.
pub fn TextureUV(texture_handle: u32, local_uv: Vec2(f32), tex_width: u32, tex_height: u32) Vec3(f32) {
    return TextureManager.GetTextureUV(texture_handle, local_uv, tex_width, tex_height);
}

/// `glyph_uv` is where in the glyph's box, from rayIMGlyph. TextureUV0/1 are the glyph's
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

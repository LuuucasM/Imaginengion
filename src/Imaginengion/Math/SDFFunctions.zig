const MathTypes = @import("MathTypes.zig");
const Vec3 = MathTypes.Vec3;
const Quat = MathTypes.Quat;
const Vec2 = MathTypes.Vec2;
const Vec4 = MathTypes.Vec4;

const ShapeData = @import("../Renderer/Renderer2D.zig").ShapeData;
const SurfShadingData = @import("../Renderer/Renderer.zig").SurfShadingData;

const TextureManager = @import("../TextureManager/TextureManager.zig");

const RayIntersect = @import("RayIntersect.zig");
const HitInfo = RayIntersect.HitInfo;
const Aabb = @import("Aabb.zig");
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

/// The bounding box of a box of `half_extents` centered on `center` and turned so its own axes point along `axis_x`,
/// `axis_y` and `axis_z` (unit length, in world space). Each of its axes reaches |axis| times its half extent along
/// the world axes, and those add up. Exact: it touches the box's furthest corner on every side, however it is turned
pub fn aabbBox(center: Vec3(f32), axis_x: Vec3(f32), axis_y: Vec3(f32), axis_z: Vec3(f32), half_extents: Vec3(f32)) Aabb {
    const reach = axis_x.Abs().MulScalar(half_extents.x)
        .AddVec(axis_y.Abs().MulScalar(half_extents.y))
        .AddVec(axis_z.Abs().MulScalar(half_extents.z));
    return .{ .Min = center.SubVec(reach), .Max = center.AddVec(reach) };
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

/// A world point in a shape's own space, where it is axis aligned and centered on the origin, by its precomputed axes
pub fn ShapeLocalPoint(shape: ShapeData, point: Vec3(f32)) Vec3(f32) {
    const axis_x: Vec4(f32) = .FromVector(shape.AxisX);
    const axis_y: Vec4(f32) = .FromVector(shape.AxisY);
    const axis_z: Vec4(f32) = .FromVector(shape.AxisZ);
    return .{
        .x = axis_x.ToVec3().Dot(point) + axis_x.w,
        .y = axis_y.ToVec3().Dot(point) + axis_y.w,
        .z = axis_z.ToVec3().Dot(point) + axis_z.w,
    };
}

/// A world direction in a shape's own space: turned, not moved
pub fn ShapeLocalDir(shape: ShapeData, dir: Vec3(f32)) Vec3(f32) {
    return .{
        .x = Vec4(f32).FromVector(shape.AxisX).ToVec3().Dot(dir),
        .y = Vec4(f32).FromVector(shape.AxisY).ToVec3().Dot(dir),
        .z = Vec4(f32).FromVector(shape.AxisZ).ToVec3().Dot(dir),
    };
}

/// A direction in a shape's own space back in world space, the other way from ShapeLocalDir: along each of its axes
pub fn ShapeWorldDir(shape: ShapeData, local_dir: Vec3(f32)) Vec3(f32) {
    return Vec4(f32).FromVector(shape.AxisX).ToVec3().MulScalar(local_dir.x)
        .AddVec(Vec4(f32).FromVector(shape.AxisY).ToVec3().MulScalar(local_dir.y))
        .AddVec(Vec4(f32).FromVector(shape.AxisZ).ToVec3().MulScalar(local_dir.z));
}

/// Where a shape is centered, back out of its precomputed axes: each axis's w is -dot(axis, center), and the axes are
/// at right angles to each other and unit length, so the center is minus the sum of each axis times its w
pub fn ShapeCenter(shape: ShapeData) Vec3(f32) {
    const axis_x: Vec4(f32) = .FromVector(shape.AxisX);
    const axis_y: Vec4(f32) = .FromVector(shape.AxisY);
    const axis_z: Vec4(f32) = .FromVector(shape.AxisZ);
    return axis_x.ToVec3().MulScalar(-axis_x.w)
        .AddVec(axis_y.ToVec3().MulScalar(-axis_y.w))
        .AddVec(axis_z.ToVec3().MulScalar(-axis_z.w));
}

/// aabbBox for a shape whose bounds are its Size box, turned by its axes
fn aabbIMBoxShape(shape: ShapeData) Aabb {
    return aabbBox(
        ShapeCenter(shape),
        Vec4(f32).FromVector(shape.AxisX).ToVec3(),
        Vec4(f32).FromVector(shape.AxisY).ToVec3(),
        Vec4(f32).FromVector(shape.AxisZ).ToVec3(),
        .FromVector(shape.Size),
    );
}

/// A quad's bounding box: its whole plate. Rounded corners only cut into it, so the box around the square one still
/// touches its flat sides and is as tight as any box can be
pub fn aabbIMQuad(quad: ShapeData) Aabb {
    return aabbIMBoxShape(quad);
}

/// A glyph's bounding box: its box
pub fn aabbIMGlyph(glyph: ShapeData) Aabb {
    return aabbIMBoxShape(glyph);
}

/// Any shape's bounding box, by its kind: the aabb function of each, the way the shader picks each one's sd and ray
/// functions. A new kind of shape adds its own here
pub fn aabbIMShape(shape: ShapeData) Aabb {
    return switch (shape.Type) {
        .Quad => aabbIMQuad(shape),
        .Glyph => aabbIMGlyph(shape),
        //the rectangle its parts lie within
        .Merge => aabbIMBoxShape(shape),
        .None => Aabb.empty,
    };
}

fn HasSquareCorners(quad: ShapeData) bool {
    const radii: Vec4(f32) = .FromVector(quad.Params);
    return radii.x == 0 and radii.y == 0 and radii.z == 0 and radii.w == 0;
}

/// A quad is a thin plate: its 2D rounded box extruded to its thickness. Square corners (radii of 0) make it
/// exactly the plain box, which is what one with them gets, without the rounding's math. Its corner radii are its Params
pub fn sdIMQuad(point: Vec3(f32), quad: ShapeData) f32 {
    const local_point = ShapeLocalPoint(quad, point);
    const half_extents: Vec3(f32) = .FromVector(quad.Size);
    if (HasSquareCorners(quad)) return sdBox(local_point, half_extents);
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
    const local_point = ShapeLocalPoint(quad, point);
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

/// iq's opUnion: inside either shape, so the distance to it is the nearer of the two
pub fn opUnion(distance_a: f32, distance_b: f32) f32 {
    return @min(distance_a, distance_b);
}

/// iq's opSubtraction: a with b cut out of it, inside a and outside b. b's inside turned outward is what bounds it,
/// which is why both have to be signed
pub fn opSubtraction(distance_a: f32, distance_b: f32) f32 {
    return @max(distance_a, -distance_b);
}

/// Two shapes combined smoothly, and how much of b is in the result: 0 is all a, 1 all b, what their colors are
/// mixed by. A smoothness of 0 is the sharp op exactly, with a weight of 0 or 1 (a when they tie)
pub const Blend = struct {
    D: f32,
    W: f32,
};

/// iq's quadratic smooth minimum (with its mix factor): a union that fills in where the two meet. `smoothness` is the
/// most the surface moves out, right where they are the same distance; the blend reaches to where they are 4 times
/// that apart
pub fn opSmoothUnion(distance_a: f32, distance_b: f32, smoothness: f32) Blend {
    if (smoothness <= 0) {
        return if (distance_a <= distance_b) .{ .D = distance_a, .W = 0 } else .{ .D = distance_b, .W = 1 };
    }
    const k = smoothness * 4.0;
    const h = @max(k - @abs(distance_a - distance_b), 0.0) / k;
    const m = h * h * 0.5;
    const s = m * k * 0.5;
    return if (distance_a < distance_b) .{ .D = distance_a - s, .W = m } else .{ .D = distance_b - s, .W = 1.0 - m };
}

/// The smooth maximum, opSmoothUnion turned inside out: what the smooth subtract and intersect are made of
fn SmoothMax(distance_a: f32, distance_b: f32, smoothness: f32) Blend {
    const inverted = opSmoothUnion(-distance_a, -distance_b, smoothness);
    return .{ .D = -inverted.D, .W = inverted.W };
}

/// opSubtraction with the edge of the cut rounded off by `smoothness`. The weight is how much of the cutter's side the
/// result is on
pub fn opSmoothSubtraction(distance_a: f32, distance_b: f32, smoothness: f32) Blend {
    return SmoothMax(distance_a, -distance_b, smoothness);
}

/// opIntersection with the edge where the two meet rounded off by `smoothness`
pub fn opSmoothIntersection(distance_a: f32, distance_b: f32, smoothness: f32) Blend {
    return SmoothMax(distance_a, distance_b, smoothness);
}

/// A texture UV that means "no texture, just the surface's color", for surfaces like a border that are a
/// solid color. A real UV's layer is never negative
pub const UNTEXTURED_UV: Vec3(f32) = .{ .x = 0, .y = 0, .z = -2 };

pub fn sdIMGlyph(point: Vec3(f32), glyph: ShapeData) f32 {
    return sdBox(ShapeLocalPoint(glyph, point), .FromVector(glyph.Size));
}

/// The ray against the quad's box: where it hits, which face, and where on it. Tested in the quad's own space, with
/// the normal turned back into world space
pub fn rayIMQuad(ray: Ray, quad: ShapeData) HitInfo {
    var hit = RayIntersect.RayRoundedBox2DLocal(ShapeLocalPoint(quad, ray.Origin), ShapeLocalDir(quad, ray.Dir), .FromVector(quad.Size), .FromVector(quad.Params));
    if (hit.IsHit()) hit.Normal = ShapeWorldDir(quad, hit.Normal);
    return hit;
}

/// The ray against the glyph's box, the same way as rayIMQuad.
/// UV is where in the glyph's box, which is what GetMSD and TextureUV take, not a texture manager UV.
pub fn rayIMGlyph(ray: Ray, glyph: ShapeData) HitInfo {
    var hit = RayIntersect.RayBoxLocal(ShapeLocalPoint(glyph, ray.Origin), ShapeLocalDir(glyph, ray.Dir), .FromVector(glyph.Size));
    if (hit.IsHit()) hit.Normal = ShapeWorldDir(glyph, hit.Normal);
    return hit;
}

/// The ray against a merge's box, its plate over the rectangle its parts lie within, the same way as rayIMGlyph: where
/// in the box it is hit decides nothing, its program does (SDFProgram)
pub fn rayIMMerge(ray: Ray, merge: ShapeData) HitInfo {
    return rayIMGlyph(ray, merge);
}

/// A 0 to 1 position within a texture, as the texture manager's UV for that texture's slot.
pub fn TextureUV(texture_handle: u32, local_uv: Vec2(f32), tex_width: u32, tex_height: u32) Vec3(f32) {
    return TextureManager.GetTextureUV(texture_handle, local_uv, tex_width, tex_height);
}

/// `face_uv` (0 to 1 across a shape's face, bottom left (0, 0)) as a spot in the part of the texture the shading
/// covers, TextureUV0 to TextureUV1. The texture still 0 to 1 over itself, TextureUV turns it into its slot
pub fn SurfaceUV(shading_data: SurfShadingData, face_uv: Vec2(f32)) Vec2(f32) {
    //uv0 + (uv1 - uv0) * t. multiplying after the add instead gives uv1 * t, which for a glyph samples everything
    //from the atlas corner to the glyph and paints a patch of other glyphs into this one's box
    const uv0 = Vec2(f32).FromArray(shading_data.TextureUV0);
    return uv0.AddVec(Vec2(f32).FromArray(shading_data.TextureUV1).SubVec(uv0).MulVec(face_uv));
}

/// `glyph_uv` is where in the glyph's box, from rayIMGlyph. TextureUV0/1 are the glyph's
/// bottom-left and top-right in the atlas: textures load flipped so v runs bottom up, the same as
/// the font json's yOrigin bottom, and the same as glyph_uv.
pub fn GetMSD(glyph_uv: Vec2(f32), atlas_shading_data: SurfShadingData, textures_array: anytype, sample_sampler: anytype) f32 {
    const raw_uv = SurfaceUV(atlas_shading_data, glyph_uv);
    const sample_uv = TextureManager.GetTextureUV(atlas_shading_data.Texturehandle, raw_uv, atlas_shading_data.TextureWidth, atlas_shading_data.TextureHeight);
    const msd = sample_sampler(textures_array, sample_uv.ToVector(), 0.0);
    return Median(msd[0], msd[1], msd[2]);
}

fn Median(a: f32, b: f32, c: f32) f32 {
    return @max(@min(a, b), @min(@max(a, b), c));
}

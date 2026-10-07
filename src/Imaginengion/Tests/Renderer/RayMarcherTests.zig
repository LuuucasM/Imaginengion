//! The SDF ray marcher the compute shaders run, run on the CPU instead: plain arrays for its buffers and a stand in
//! for the texture array. Each test traces one ray the way SDFComputeGame's main does and checks the color it comes
//! out with, so what a pixel shows can be pinned down without a GPU. Run with `zig build test-engine`.
const std = @import("std");
const MathTypes = @import("../../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;
const Vec3 = MathTypes.Vec3;
const Vec4 = MathTypes.Vec4;
const Quat = MathTypes.Quat;
const Ray = @import("../../Math/CameraRay.zig").Ray;
const SDFFunc = @import("../../Math/SDFFunctions.zig");
const TextureManager = @import("../../TextureManager/TextureManager.zig");
const BINS_BYTES = @import("../../TextureManager/backends/SGTextureManager.zig").BINS_BYTES;

const Renderer2D = @import("../../Renderer/Renderer2D.zig");
const ShapeData = Renderer2D.ShapeData;
const ShapeSurface = Renderer2D.ShapeSurface;
const ClipData = Renderer2D.ClipData;
const Renderer = @import("../../Renderer/Renderer.zig");
const SurfShadingData = Renderer.SurfShadingData;
const MedShadingData = Renderer.MedShadingData;
const SDFRayMarcher = @import("../../Renderer/SDFRayMarcher.zig");
const BVH = @import("../../Core/BVH.zig");

const eps: f32 = 0.0001;

const IDENTITY = Quat(f32){ .w = 1, .x = 0, .y = 0, .z = 0 };
//what a ray that hits nothing comes out as, SDFComputeGame's sky
const DEFAULT_COLOR = Vec4(f32){ .x = 0, .y = 0.28, .z = 0.39, .w = 1.0 };
const FAR: f32 = 100;

const RED = Vec4(f32){ .x = 1, .y = 0, .z = 0, .w = 1 };
const GREEN = Vec4(f32){ .x = 0, .y = 1, .z = 0, .w = 1 };
const BLUE = Vec4(f32){ .x = 0, .y = 0, .z = 1, .w = 1 };
const WHITE = Vec4(f32){ .x = 1, .y = 1, .z = 1, .w = 1 };

//==================================the stand in texture array==================================

/// Texture manager handles in bin 0, slot 0 of a layer, so the layer alone says which stand in texture a sample is from
fn LayerHandle(layer: u32) u32 {
    return layer << BINS_BYTES;
}

const TEX_SIZE: u32 = 64;
/// plain white: a quad's surface comes out as its shading color
const WHITE_HANDLE = LayerHandle(0);
/// a glyph atlas whose one letter covers the left half of its box, and leaves a gap on the right
const ATLAS_HANDLE = LayerHandle(1);
/// plain green: the fill a glyph's letter is painted with
const GREEN_HANDLE = LayerHandle(2);

const FakeTextures = struct {};
const TEXTURES = FakeTextures{};

/// What the shaders' imageSampleExplicitLod does: a color from the texture array at a UV and layer
fn FakeSample(_: *const FakeTextures, uv_layer: @Vector(3, f32), _: f32) @Vector(4, f32) {
    const layer: u32 = @intFromFloat(uv_layer[2]);
    if (layer == TextureManager.GetLayerIndex(ATLAS_HANDLE)) {
        //the letter's edge is half way across the glyph, where the atlas UV of glyph u = 0.5 is
        const edge = TextureManager.GetTextureUV(ATLAS_HANDLE, .{ .x = 0.5, .y = 0 }, TEX_SIZE, TEX_SIZE).x;
        return if (uv_layer[0] < edge) .{ 1, 1, 1, 1 } else .{ 0, 0, 0, 1 };
    }
    if (layer == TextureManager.GetLayerIndex(GREEN_HANDLE)) return GREEN.ToVector();
    return WHITE.ToVector();
}

//==================================building a scene==================================

fn Shading(color: Vec4(f32), texture_handle: u32, sibling_shading: u32) SurfShadingData {
    return .{
        .Color = color.ToArray(),
        .TextureUV0 = .{ 0, 0 },
        .TextureUV1 = .{ 1, 1 },
        .TilingFactor = 1,
        .Texturehandle = texture_handle,
        .SiblingShading = sibling_shading,
        .TextureWidth = TEX_SIZE,
        .TextureHeight = TEX_SIZE,
    };
}

/// A plain colored surface, on the white texture
fn ColorShading(color: Vec4(f32)) SurfShadingData {
    return Shading(color, WHITE_HANDLE, std.math.maxInt(u32));
}

/// A shape and its surface, which Trace puts in their two buffers the way Renderer2D does
const TestShape = struct {
    Shape: ShapeData,
    Surface: ShapeSurface,
    /// When it was drawn, which is its SurfaceIndex. Its place in the scene's list when null. Set it to have the shape
    /// buffer's order differ from the draw order, the way sorting the shapes for the BVH leaves them
    DrawOrder: ?u32 = null,
};

fn MakeQuad(center: Vec3(f32), rotation: Quat(f32), half: Vec2(f32), shading: u32, flags: u32, clip_index: u32) TestShape {
    return MakeRoundedQuad(center, rotation, half, 0, shading, flags, clip_index);
}

/// A quad with every corner rounded by `radius`. 0 is a square cornered one, which takes the plain box's fast path
fn MakeRoundedQuad(center: Vec3(f32), rotation: Quat(f32), half: Vec2(f32), radius: f32, shading: u32, flags: u32, clip_index: u32) TestShape {
    const axes = Renderer2D.ShapeAxes(center, rotation);
    return .{
        .Shape = .{
            .AxisX = axes[0],
            .AxisY = axes[1],
            .AxisZ = axes[2],
            .Size = .{ half.x, half.y, SDFFunc.THICKNESS_2D },
            .Params = .{ radius, radius, radius, radius },
            .Type = .Quad,
            .ClipIndex = clip_index,
            .SurfaceIndex = undefined,
            .Flags = flags,
        },
        .Surface = .{ .ShadingHandle = shading, .BorderShadingHandle = shading, .BorderWidth = 0 },
    };
}

fn MakeGlyph(center: Vec3(f32), half: Vec2(f32), atlas_shading: u32, flags: u32) TestShape {
    const axes = Renderer2D.ShapeAxes(center, IDENTITY);
    return .{
        .Shape = .{
            .AxisX = axes[0],
            .AxisY = axes[1],
            .AxisZ = axes[2],
            .Size = .{ half.x, half.y, SDFFunc.THICKNESS_2D },
            .Params = .{ 0, 0, 0, 0 },
            .Type = .Glyph,
            .ClipIndex = SDFFunc.NO_CLIP,
            .SurfaceIndex = undefined,
            .Flags = flags,
        },
        .Surface = .{ .ShadingHandle = atlas_shading, .BorderShadingHandle = atlas_shading, .BorderWidth = 0 },
    };
}

fn MakeClip(center: Vec3(f32), half: Vec2(f32)) ClipData {
    return .{ .Rotation = IDENTITY.ToArray(), .Position = center.ToArray(), .HalfExtents = half.ToArray() };
}

const TRANSPARENT = ShapeData.FLAG_TRANSPARENT;

//a medium that changes nothing a ray passes through
const CLEAR_MEDIUM = MedShadingData{ .Color = .{ 0, 0, 0, 0 }, .Absorption = .{ 0, 0, 0 }, .Scattering = .{ 0, 0, 0 } };

const TestScene = struct {
    Shapes: []const TestShape = &.{},
    Clips: []const ClipData = &.{},
    Shadings: []const SurfShadingData,
    //by an edge's MaterialHandle, which is always 0 so far
    Mediums: []const MedShadingData = &.{CLEAR_MEDIUM},
};

const TestMarcher = SDFRayMarcher.RayMarcher(
    [*]const ShapeData,
    [*]const ShapeSurface,
    [*]const BVH.Node,
    [*]const ClipData,
    [*]const SurfShadingData,
    [*]const MedShadingData,
    *const FakeTextures,
);

const MAX_TEST_SHAPES = 32;

const NO_BVH_NODES = [0]BVH.Node{};

/// The color one ray comes out with, found both ways a shape can be: with every shape direct (a ray test straight
/// against each) and with every shape marched. The two have to agree, which keeps the march working while nothing
/// the engine draws uses it yet
fn Trace(scene: TestScene, ray: Ray) !Vec4(f32) {
    const direct = TraceWith(scene, ray, scene.Shapes.len);
    const marched = TraceWith(scene, ray, 0);
    ExpectColor(direct, marched) catch |err| {
        std.debug.print("all direct and all marched disagree: direct {any}, marched {any}\n", .{ direct, marched });
        return err;
    };
    return direct;
}

/// The color one ray comes out with when the first `direct_count` shapes are direct and the rest marched, set up the
/// way SDFComputeGame's main sets up a pixel's ray
fn TraceWith(scene: TestScene, ray: Ray, direct_count: usize) Vec4(f32) {
    std.debug.assert(scene.Shadings.len > 0);
    std.debug.assert(scene.Shapes.len <= MAX_TEST_SHAPES and direct_count <= scene.Shapes.len);

    var shapes: [MAX_TEST_SHAPES]ShapeData = undefined;
    var surfaces: [MAX_TEST_SHAPES]ShapeSurface = undefined;
    //surfaces are in draw order, the shapes wherever the scene put them, the way Renderer2D uploads them once sorted
    for (scene.Shapes, 0..) |test_shape, i| {
        const draw_order: u32 = test_shape.DrawOrder orelse @intCast(i);
        shapes[i] = test_shape.Shape;
        shapes[i].SurfaceIndex = draw_order;
        surfaces[draw_order] = test_shape.Surface;
    }

    var marcher = TestMarcher{
        .mNodes = undefined,
        .mEdges = undefined,
        .mNodeCount = 0,
        .mEdgeCount = 0,
        .mDefaultColor = DEFAULT_COLOR,
        .mShapes = &shapes,
        .mShapeSurfaces = &surfaces,
        .mShapesCount = scene.Shapes.len,
        .mDirectCount = direct_count,
        //not walked yet: the direct search still tests every direct shape
        .mBVHNodes = &NO_BVH_NODES,
        .mClips = scene.Clips.ptr,
        .mSurfShading = scene.Shadings.ptr,
        .mMedShading = scene.Mediums.ptr,
        .mPerspectiveFar = FAR,
    };

    marcher.mNodes[0] = .{
        .Point = ray.Origin,
        .Normal = .{ .x = 0, .y = 0, .z = 0 },
        .ParentEdge = TestMarcher.NO_EDGE,
        .FirstEdge = TestMarcher.NO_EDGE,
        .MaterialHandle = 0,
        .AccumColor = DEFAULT_COLOR,
        .TextureUV = .{ .x = -1, .y = -1, .z = -1 },
        .ShapeT = .None,
    };
    marcher.mNodeCount = 1;

    marcher.mEdges[0] = .{
        .Direction = ray.Dir,
        .Length = 0.0,
        .FromNode = 0,
        .ToNode = 0,
        .SiblingEdge = TestMarcher.NO_EDGE,
        .AccumColor = DEFAULT_COLOR,
        .MaterialHandle = 0,
    };
    marcher.mNodes[0].FirstEdge = 0;
    marcher.mEdgeCount = 1;

    marcher.March(FakeSample, &TEXTURES);
    return marcher.GenerateColor(FakeSample, &TEXTURES);
}

/// Straight down -z from in front of everything, at (x, y)
fn RayAt(x: f32, y: f32) Ray {
    return .{ .Origin = .{ .x = x, .y = y, .z = 10 }, .Dir = .{ .x = 0, .y = 0, .z = -1 } };
}

fn ExpectColor(expected: Vec4(f32), actual: Vec4(f32)) !void {
    try std.testing.expectApproxEqAbs(expected.x, actual.x, eps);
    try std.testing.expectApproxEqAbs(expected.y, actual.y, eps);
    try std.testing.expectApproxEqAbs(expected.z, actual.z, eps);
    try std.testing.expectApproxEqAbs(expected.w, actual.w, eps);
}

//==================================hitting and missing==================================

test "a ray that hits nothing comes out as the default color" {
    const shadings = [_]SurfShadingData{ColorShading(RED)};
    const shapes = [_]TestShape{MakeQuad(.{ .x = 5, .y = 0, .z = 0 }, IDENTITY, .{ .x = 1, .y = 1 }, 0, 0, SDFFunc.NO_CLIP)};
    try ExpectColor(DEFAULT_COLOR, try Trace(.{ .Shapes = &shapes, .Shadings = &shadings }, RayAt(0, 0)));
}

test "a quad seen straight on is its color" {
    const shadings = [_]SurfShadingData{ColorShading(RED)};
    const shapes = [_]TestShape{MakeQuad(.{ .x = 0, .y = 0, .z = 0 }, IDENTITY, .{ .x = 1, .y = 1 }, 0, 0, SDFFunc.NO_CLIP)};
    try ExpectColor(RED, try Trace(.{ .Shapes = &shapes, .Shadings = &shadings }, RayAt(0.5, -0.5)));
}

test "a turned quad is hit just inside its edges and missed just past them" {
    //turned about two axes, but still facing the camera enough that its front is what is seen
    const rotation = Quat(f32).FromAxisAngle(.{ .x = 0, .y = 1, .z = 0 }, 0.5).MulQuat(Quat(f32).FromAxisAngle(.{ .x = 1, .y = 0, .z = 0 }, 0.35));
    const center = Vec3(f32){ .x = 0.3, .y = -0.2, .z = 0 };
    const half = Vec2(f32){ .x = 1, .y = 0.5 };
    const shadings = [_]SurfShadingData{ColorShading(RED)};
    const shapes = [_]TestShape{MakeQuad(center, rotation, half, 0, 0, SDFFunc.NO_CLIP)};
    const scene = TestScene{ .Shapes = &shapes, .Shadings = &shadings };

    const camera = Vec3(f32){ .x = 0, .y = 0, .z = 10 };
    const inside = center.AddVec((Vec3(f32){ .x = 0.9 * half.x, .y = 0.9 * half.y, .z = 0 }).QuatRotate(rotation));
    const past_side = center.AddVec((Vec3(f32){ .x = 1.1 * half.x, .y = 0, .z = 0 }).QuatRotate(rotation));
    const past_top = center.AddVec((Vec3(f32){ .x = 0, .y = 1.1 * half.y, .z = 0 }).QuatRotate(rotation));

    try ExpectColor(RED, try Trace(scene, .{ .Origin = camera, .Dir = inside.SubVec(camera).Dir() }));
    try ExpectColor(DEFAULT_COLOR, try Trace(scene, .{ .Origin = camera, .Dir = past_side.SubVec(camera).Dir() }));
    try ExpectColor(DEFAULT_COLOR, try Trace(scene, .{ .Origin = camera, .Dir = past_top.SubVec(camera).Dir() }));
}

test "only a quad's front is drawn" {
    const shadings = [_]SurfShadingData{ColorShading(RED)};
    const shapes = [_]TestShape{MakeQuad(.{ .x = 0, .y = 0, .z = 0 }, IDENTITY, .{ .x = 1, .y = 1 }, 0, 0, SDFFunc.NO_CLIP)};
    const from_behind = Ray{ .Origin = .{ .x = 0, .y = 0, .z = -10 }, .Dir = .{ .x = 0, .y = 0, .z = 1 } };
    try ExpectColor(DEFAULT_COLOR, try Trace(.{ .Shapes = &shapes, .Shadings = &shadings }, from_behind));
}

test "a quad past the far distance is not drawn" {
    const shadings = [_]SurfShadingData{ColorShading(RED)};
    const shapes = [_]TestShape{MakeQuad(.{ .x = 0, .y = 0, .z = -2 * FAR }, IDENTITY, .{ .x = 1, .y = 1 }, 0, 0, SDFFunc.NO_CLIP)};
    try ExpectColor(DEFAULT_COLOR, try Trace(.{ .Shapes = &shapes, .Shadings = &shadings }, RayAt(0, 0)));
}

test "a ray grazing just past a thin quad misses it" {
    //nearly along the quad's face, passing above it by a few times its thickness: the case that used to creep along
    //a step at a time
    const shadings = [_]SurfShadingData{ColorShading(RED)};
    const shapes = [_]TestShape{MakeQuad(.{ .x = 0, .y = 0, .z = 0 }, IDENTITY, .{ .x = 1, .y = 1 }, 0, 0, SDFFunc.NO_CLIP)};
    const grazing = Ray{
        .Origin = .{ .x = -20, .y = 0, .z = 0.01 },
        .Dir = (Vec3(f32){ .x = 1, .y = 0, .z = -0.0001 }).Dir(),
    };
    try ExpectColor(DEFAULT_COLOR, try Trace(.{ .Shapes = &shapes, .Shadings = &shadings }, grazing));
}

//==================================which shape is in front==================================

test "the nearer of two overlapping quads is drawn, whichever order they are in" {
    const shadings = [_]SurfShadingData{ ColorShading(RED), ColorShading(BLUE) };
    const near = MakeQuad(.{ .x = 0, .y = 0, .z = 1 }, IDENTITY, .{ .x = 1, .y = 1 }, 0, 0, SDFFunc.NO_CLIP);
    const far = MakeQuad(.{ .x = 0, .y = 0, .z = 0 }, IDENTITY, .{ .x = 1, .y = 1 }, 1, 0, SDFFunc.NO_CLIP);

    const near_first = [_]TestShape{ near, far };
    const far_first = [_]TestShape{ far, near };
    try ExpectColor(RED, try Trace(.{ .Shapes = &near_first, .Shadings = &shadings }, RayAt(0, 0)));
    try ExpectColor(RED, try Trace(.{ .Shapes = &far_first, .Shadings = &shadings }, RayAt(0, 0)));
}

//How exact ties come out today. Step 4 of the renderer plan picks a tie rule on purpose; if it changes these,
//change them with it rather than to make them pass
test "of two quads at the same depth, the one drawn first is drawn" {
    const shadings = [_]SurfShadingData{ ColorShading(RED), ColorShading(BLUE) };
    const shapes = [_]TestShape{
        MakeQuad(.{ .x = 0, .y = 0, .z = 0 }, IDENTITY, .{ .x = 1, .y = 1 }, 0, 0, SDFFunc.NO_CLIP),
        MakeQuad(.{ .x = 0, .y = 0, .z = 0 }, IDENTITY, .{ .x = 1, .y = 1 }, 1, 0, SDFFunc.NO_CLIP),
    };
    try ExpectColor(RED, try Trace(.{ .Shapes = &shapes, .Shadings = &shadings }, RayAt(0, 0)));
}

test "a tie at the same depth goes by draw order, wherever sorting put the shapes in the buffer" {
    //the red quad was drawn first, but the BVH's sort put the blue one ahead of it in the shape buffer
    const shadings = [_]SurfShadingData{ ColorShading(RED), ColorShading(BLUE) };
    var red = MakeQuad(.{ .x = 0, .y = 0, .z = 0 }, IDENTITY, .{ .x = 1, .y = 1 }, 0, 0, SDFFunc.NO_CLIP);
    red.DrawOrder = 0;
    var blue = MakeQuad(.{ .x = 0, .y = 0, .z = 0 }, IDENTITY, .{ .x = 1, .y = 1 }, 1, 0, SDFFunc.NO_CLIP);
    blue.DrawOrder = 1;
    const shapes = [_]TestShape{ blue, red };
    try ExpectColor(RED, try Trace(.{ .Shapes = &shapes, .Shadings = &shadings }, RayAt(0, 0)));
}

test "a quad and a glyph at the same depth: the quad is drawn, whichever comes first in the buffer" {
    //the glyph's letter covers its left half, which is where the ray goes
    const shadings = [_]SurfShadingData{
        ColorShading(RED),
        Shading(WHITE, ATLAS_HANDLE, 2),
        Shading(WHITE, GREEN_HANDLE, std.math.maxInt(u32)),
    };
    const quad = MakeQuad(.{ .x = 0, .y = 0, .z = 0 }, IDENTITY, .{ .x = 1, .y = 1 }, 0, 0, SDFFunc.NO_CLIP);
    const glyph = MakeGlyph(.{ .x = 0, .y = 0, .z = 0 }, .{ .x = 0.5, .y = 0.5 }, 1, 0);

    const quad_first = [_]TestShape{ quad, glyph };
    const glyph_first = [_]TestShape{ glyph, quad };
    try ExpectColor(RED, try Trace(.{ .Shapes = &quad_first, .Shadings = &shadings }, RayAt(-0.25, 0)));
    try ExpectColor(RED, try Trace(.{ .Shapes = &glyph_first, .Shadings = &shadings }, RayAt(-0.25, 0)));
}

//==================================seeing through==================================

test "a see-through quad blends with the quad behind it" {
    const half_red = Vec4(f32){ .x = 1, .y = 0, .z = 0, .w = 0.5 };
    const shadings = [_]SurfShadingData{ ColorShading(half_red), ColorShading(BLUE) };
    const shapes = [_]TestShape{
        MakeQuad(.{ .x = 0, .y = 0, .z = 1 }, IDENTITY, .{ .x = 1, .y = 1 }, 0, TRANSPARENT, SDFFunc.NO_CLIP),
        MakeQuad(.{ .x = 0, .y = 0, .z = 0 }, IDENTITY, .{ .x = 1, .y = 1 }, 1, 0, SDFFunc.NO_CLIP),
    };
    //half of each, and the alpha half way from the front's 0.5 to the back's 1
    try ExpectColor(.{ .x = 0.5, .y = 0, .z = 0.5, .w = 0.75 }, try Trace(.{ .Shapes = &shapes, .Shadings = &shadings }, RayAt(0, 0)));
}

test "a see-through quad with nothing behind it blends with the default color" {
    const half_red = Vec4(f32){ .x = 1, .y = 0, .z = 0, .w = 0.5 };
    const shadings = [_]SurfShadingData{ColorShading(half_red)};
    const shapes = [_]TestShape{MakeQuad(.{ .x = 0, .y = 0, .z = 0 }, IDENTITY, .{ .x = 1, .y = 1 }, 0, TRANSPARENT, SDFFunc.NO_CLIP)};
    try ExpectColor(half_red.Lerp(DEFAULT_COLOR, 0.5), try Trace(.{ .Shapes = &shapes, .Shadings = &shadings }, RayAt(0, 0)));
}

test "a stack of see-through quads blends every layer, back to front" {
    const half_red = Vec4(f32){ .x = 1, .y = 0, .z = 0, .w = 0.5 };
    const half_green = Vec4(f32){ .x = 0, .y = 1, .z = 0, .w = 0.5 };
    const shadings = [_]SurfShadingData{ ColorShading(half_red), ColorShading(half_green), ColorShading(BLUE) };
    const shapes = [_]TestShape{
        MakeQuad(.{ .x = 0, .y = 0, .z = 0 }, IDENTITY, .{ .x = 1, .y = 1 }, 2, 0, SDFFunc.NO_CLIP),
        MakeQuad(.{ .x = 0, .y = 0, .z = 2 }, IDENTITY, .{ .x = 1, .y = 1 }, 0, TRANSPARENT, SDFFunc.NO_CLIP),
        MakeQuad(.{ .x = 0, .y = 0, .z = 1 }, IDENTITY, .{ .x = 1, .y = 1 }, 1, TRANSPARENT, SDFFunc.NO_CLIP),
    };
    const middle = half_green.Lerp(BLUE, 0.5);
    try ExpectColor(half_red.Lerp(middle, 0.5), try Trace(.{ .Shapes = &shapes, .Shadings = &shadings }, RayAt(0, 0)));
}

test "the ray past a see-through quad goes through the edge's own medium, not one picked by the quad's shading" {
    //the see-through quad is shading 1, and medium 1 is murky enough to swallow the blue behind it. The edge on
    //from the quad is still in air (medium 0), so the blend comes out the same as with only clear mediums
    const murky = MedShadingData{ .Color = .{ 0, 0, 0, 0 }, .Absorption = .{ 10, 10, 10 }, .Scattering = .{ 0, 0, 0 } };
    const mediums = [_]MedShadingData{ CLEAR_MEDIUM, murky };
    const half_red = Vec4(f32){ .x = 1, .y = 0, .z = 0, .w = 0.5 };
    const shadings = [_]SurfShadingData{ ColorShading(BLUE), ColorShading(half_red) };
    const shapes = [_]TestShape{
        MakeQuad(.{ .x = 0, .y = 0, .z = 1 }, IDENTITY, .{ .x = 1, .y = 1 }, 1, TRANSPARENT, SDFFunc.NO_CLIP),
        MakeQuad(.{ .x = 0, .y = 0, .z = 0 }, IDENTITY, .{ .x = 1, .y = 1 }, 0, 0, SDFFunc.NO_CLIP),
    };
    try ExpectColor(.{ .x = 0.5, .y = 0, .z = 0.5, .w = 0.75 }, try Trace(.{ .Shapes = &shapes, .Shadings = &shadings, .Mediums = &mediums }, RayAt(0, 0)));
}

test "a quad without the see-through flag hides what is behind it, even with a see-through color" {
    //its color still blends, but with the default color rather than the blue quad behind it
    const half_red = Vec4(f32){ .x = 1, .y = 0, .z = 0, .w = 0.5 };
    const shadings = [_]SurfShadingData{ ColorShading(half_red), ColorShading(BLUE) };
    const shapes = [_]TestShape{
        MakeQuad(.{ .x = 0, .y = 0, .z = 1 }, IDENTITY, .{ .x = 1, .y = 1 }, 0, 0, SDFFunc.NO_CLIP),
        MakeQuad(.{ .x = 0, .y = 0, .z = 0 }, IDENTITY, .{ .x = 1, .y = 1 }, 1, 0, SDFFunc.NO_CLIP),
    };
    try ExpectColor(half_red.Lerp(DEFAULT_COLOR, 0.5), try Trace(.{ .Shapes = &shapes, .Shadings = &shadings }, RayAt(0, 0)));
}

//==================================cut off and gaps==================================

test "a clipped quad is only drawn inside its clip region, and the ray goes on past the rest" {
    //the red quad is cut to its left half, the blue one behind it isn't cut at all
    const shadings = [_]SurfShadingData{ ColorShading(RED), ColorShading(BLUE) };
    const clips = [_]ClipData{MakeClip(.{ .x = -1, .y = 0, .z = 0 }, .{ .x = 1, .y = 2 })};
    const shapes = [_]TestShape{
        MakeQuad(.{ .x = 0, .y = 0, .z = 1 }, IDENTITY, .{ .x = 1, .y = 1 }, 0, 0, 0),
        MakeQuad(.{ .x = 0, .y = 0, .z = 0 }, IDENTITY, .{ .x = 1, .y = 1 }, 1, 0, SDFFunc.NO_CLIP),
    };
    const scene = TestScene{ .Shapes = &shapes, .Clips = &clips, .Shadings = &shadings };
    try ExpectColor(RED, try Trace(scene, RayAt(-0.5, 0)));
    try ExpectColor(BLUE, try Trace(scene, RayAt(0.5, 0)));
}

test "a glyph is drawn where its letter covers it, and the ray goes through its gaps" {
    //the letter covers the glyph's left half and is filled green; a blue quad sits behind
    const shadings = [_]SurfShadingData{
        ColorShading(BLUE),
        Shading(WHITE, ATLAS_HANDLE, 2),
        Shading(WHITE, GREEN_HANDLE, std.math.maxInt(u32)),
    };
    const shapes = [_]TestShape{
        MakeQuad(.{ .x = 0, .y = 0, .z = 0 }, IDENTITY, .{ .x = 1, .y = 1 }, 0, 0, SDFFunc.NO_CLIP),
        MakeGlyph(.{ .x = 0, .y = 0, .z = 1 }, .{ .x = 0.5, .y = 0.5 }, 1, 0),
    };
    const scene = TestScene{ .Shapes = &shapes, .Shadings = &shadings };
    try ExpectColor(GREEN, try Trace(scene, RayAt(-0.25, 0)));
    try ExpectColor(BLUE, try Trace(scene, RayAt(0.25, 0)));
}

test "a glyph is tinted by its text's color" {
    //the text's fill is grey on a plain white texture, the way StyleSystem colors text. The atlas entry is always
    //white, and only says where the letter is
    const grey = Vec4(f32){ .x = 0.5, .y = 0.5, .z = 0.5, .w = 1 };
    const shadings = [_]SurfShadingData{
        Shading(WHITE, ATLAS_HANDLE, 1),
        ColorShading(grey),
    };
    const shapes = [_]TestShape{MakeGlyph(.{ .x = 0, .y = 0, .z = 0 }, .{ .x = 0.5, .y = 0.5 }, 0, 0)};
    try ExpectColor(grey, try Trace(.{ .Shapes = &shapes, .Shadings = &shadings }, RayAt(-0.25, 0)));
}

test "see-through text blends with what is behind it" {
    //half see-through red text, flagged the way StyleSystem flags a text color with alpha below 1, over a blue quad
    const half_red = Vec4(f32){ .x = 1, .y = 0, .z = 0, .w = 0.5 };
    const shadings = [_]SurfShadingData{
        ColorShading(BLUE),
        Shading(WHITE, ATLAS_HANDLE, 2),
        ColorShading(half_red),
    };
    const shapes = [_]TestShape{
        MakeQuad(.{ .x = 0, .y = 0, .z = 0 }, IDENTITY, .{ .x = 1, .y = 1 }, 0, 0, SDFFunc.NO_CLIP),
        MakeGlyph(.{ .x = 0, .y = 0, .z = 1 }, .{ .x = 0.5, .y = 0.5 }, 1, TRANSPARENT),
    };
    try ExpectColor(.{ .x = 0.5, .y = 0, .z = 0.5, .w = 0.75 }, try Trace(.{ .Shapes = &shapes, .Shadings = &shadings }, RayAt(-0.25, 0)));
}

test "a ray through the gaps of several overlapping glyphs at the same depth reaches what is behind them" {
    //three glyph boxes on top of each other, the way neighbouring letters' boxes overlap. Every letter covers the left
    //half, so on the right the ray is turned down by each in turn before it gets to the blue quad behind
    const shadings = [_]SurfShadingData{
        ColorShading(BLUE),
        Shading(WHITE, ATLAS_HANDLE, 2),
        Shading(WHITE, GREEN_HANDLE, std.math.maxInt(u32)),
    };
    const glyph = MakeGlyph(.{ .x = 0, .y = 0, .z = 1 }, .{ .x = 0.5, .y = 0.5 }, 1, 0);
    const shapes = [_]TestShape{
        glyph,
        glyph,
        MakeQuad(.{ .x = 0, .y = 0, .z = 0 }, IDENTITY, .{ .x = 1, .y = 1 }, 0, 0, SDFFunc.NO_CLIP),
        glyph,
    };
    const scene = TestScene{ .Shapes = &shapes, .Shadings = &shadings };
    try ExpectColor(GREEN, try Trace(scene, RayAt(-0.25, 0)));
    try ExpectColor(BLUE, try Trace(scene, RayAt(0.25, 0)));
}

//==================================direct and marched together==================================

test "a marched quad in front of a direct quad is drawn" {
    //the blue quad is direct and the red one in front of it marched
    const shadings = [_]SurfShadingData{ ColorShading(BLUE), ColorShading(RED) };
    const shapes = [_]TestShape{
        MakeQuad(.{ .x = 0, .y = 0, .z = 0 }, IDENTITY, .{ .x = 1, .y = 1 }, 0, 0, SDFFunc.NO_CLIP),
        MakeQuad(.{ .x = 0, .y = 0, .z = 1 }, IDENTITY, .{ .x = 1, .y = 1 }, 1, 0, SDFFunc.NO_CLIP),
    };
    try ExpectColor(RED, TraceWith(.{ .Shapes = &shapes, .Shadings = &shadings }, RayAt(0, 0), 1));
}

test "a direct quad in front hides a marched one behind it, which still shows past the direct one's edge" {
    //the small red quad is direct, the bigger blue one behind it marched
    const shadings = [_]SurfShadingData{ ColorShading(RED), ColorShading(BLUE) };
    const shapes = [_]TestShape{
        MakeQuad(.{ .x = 0, .y = 0, .z = 1 }, IDENTITY, .{ .x = 0.5, .y = 0.5 }, 0, 0, SDFFunc.NO_CLIP),
        MakeQuad(.{ .x = 0, .y = 0, .z = 0 }, IDENTITY, .{ .x = 1, .y = 1 }, 1, 0, SDFFunc.NO_CLIP),
    };
    const scene = TestScene{ .Shapes = &shapes, .Shadings = &shadings };
    try ExpectColor(RED, TraceWith(scene, RayAt(0, 0), 1));
    try ExpectColor(BLUE, TraceWith(scene, RayAt(0.75, 0), 1));
}

test "the direct search turns down at most MAX_DIRECT_REJECTS hits along an edge, then counts it as a miss" {
    //a blue quad behind a stack of glyph boxes the ray goes through the gaps of. Only direct: the march's own limit
    //on what it can get past is its SkipList
    const rejects = SDFRayMarcher.MAX_DIRECT_REJECTS;
    const shadings = [_]SurfShadingData{
        ColorShading(BLUE),
        Shading(WHITE, ATLAS_HANDLE, 2),
        Shading(WHITE, GREEN_HANDLE, std.math.maxInt(u32)),
    };
    var shapes: [rejects + 2]TestShape = undefined;
    shapes[0] = MakeQuad(.{ .x = 0, .y = 0, .z = 0 }, IDENTITY, .{ .x = 1, .y = 1 }, 0, 0, SDFFunc.NO_CLIP);
    for (shapes[1..]) |*shape| shape.* = MakeGlyph(.{ .x = 0, .y = 0, .z = 1 }, .{ .x = 0.5, .y = 0.5 }, 1, 0);

    //as many gaps as it may turn down: the next search still finds the quad
    const at_limit = TestScene{ .Shapes = shapes[0 .. rejects + 1], .Shadings = &shadings };
    try ExpectColor(BLUE, TraceWith(at_limit, RayAt(0.25, 0), rejects + 1));
    //one more and it gives up
    const past_limit = TestScene{ .Shapes = shapes[0 .. rejects + 2], .Shadings = &shadings };
    try ExpectColor(DEFAULT_COLOR, TraceWith(past_limit, RayAt(0.25, 0), rejects + 2));
}

test "a quad's rounded corner is cut away: the ray goes past it there, and hits just inside the curve" {
    //every corner of the red quad is rounded by 0.5, so the top right one curves around (0.5, 0.5). A blue quad behind
    const shadings = [_]SurfShadingData{ ColorShading(RED), ColorShading(BLUE) };
    const shapes = [_]TestShape{
        MakeRoundedQuad(.{ .x = 0, .y = 0, .z = 1 }, IDENTITY, .{ .x = 1, .y = 1 }, 0.5, 0, 0, SDFFunc.NO_CLIP),
        MakeQuad(.{ .x = 0, .y = 0, .z = 0 }, IDENTITY, .{ .x = 2, .y = 2 }, 1, 0, SDFFunc.NO_CLIP),
    };
    const scene = TestScene{ .Shapes = &shapes, .Shadings = &shadings };
    //0.64 from the curve's center: in the cut away corner
    try ExpectColor(BLUE, try Trace(scene, RayAt(0.95, 0.95)));
    //0.42 from it: inside
    try ExpectColor(RED, try Trace(scene, RayAt(0.8, 0.8)));
    //well away from the corners, the flat part
    try ExpectColor(RED, try Trace(scene, RayAt(0.95, 0)));
}

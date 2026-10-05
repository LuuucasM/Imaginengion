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
};

fn MakeQuad(center: Vec3(f32), rotation: Quat(f32), half: Vec2(f32), shading: u32, flags: u32, clip_index: u32) TestShape {
    return .{
        .Shape = .{
            .Rotation = rotation.ToArray(),
            .Position = center.ToArray(),
            .Size = .{ half.x, half.y, SDFFunc.THICKNESS_2D },
            .Params = .{ 0, 0, 0, 0 },
            .Type = .Quad,
            .ClipIndex = clip_index,
            .SurfaceIndex = undefined,
            .Flags = flags,
        },
        .Surface = .{ .ShadingHandle = shading, .BorderShadingHandle = shading, .BorderWidth = 0 },
    };
}

fn MakeGlyph(center: Vec3(f32), half: Vec2(f32), atlas_shading: u32, flags: u32) TestShape {
    return .{
        .Shape = .{
            .Rotation = IDENTITY.ToArray(),
            .Position = center.ToArray(),
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
    [*]const ClipData,
    [*]const SurfShadingData,
    [*]const MedShadingData,
    *const FakeTextures,
);

const MAX_TEST_SHAPES = 16;

/// The color one ray comes out with, set up the way SDFComputeGame's main sets up a pixel's ray
fn Trace(scene: TestScene, ray: Ray) Vec4(f32) {
    std.debug.assert(scene.Shadings.len > 0);
    std.debug.assert(scene.Shapes.len <= MAX_TEST_SHAPES);

    var shapes: [MAX_TEST_SHAPES]ShapeData = undefined;
    var surfaces: [MAX_TEST_SHAPES]ShapeSurface = undefined;
    for (scene.Shapes, 0..) |test_shape, i| {
        shapes[i] = test_shape.Shape;
        shapes[i].SurfaceIndex = @intCast(i);
        surfaces[i] = test_shape.Surface;
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
    try ExpectColor(DEFAULT_COLOR, Trace(.{ .Shapes = &shapes, .Shadings = &shadings }, RayAt(0, 0)));
}

test "a quad seen straight on is its color" {
    const shadings = [_]SurfShadingData{ColorShading(RED)};
    const shapes = [_]TestShape{MakeQuad(.{ .x = 0, .y = 0, .z = 0 }, IDENTITY, .{ .x = 1, .y = 1 }, 0, 0, SDFFunc.NO_CLIP)};
    try ExpectColor(RED, Trace(.{ .Shapes = &shapes, .Shadings = &shadings }, RayAt(0.5, -0.5)));
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

    try ExpectColor(RED, Trace(scene, .{ .Origin = camera, .Dir = inside.SubVec(camera).Dir() }));
    try ExpectColor(DEFAULT_COLOR, Trace(scene, .{ .Origin = camera, .Dir = past_side.SubVec(camera).Dir() }));
    try ExpectColor(DEFAULT_COLOR, Trace(scene, .{ .Origin = camera, .Dir = past_top.SubVec(camera).Dir() }));
}

test "only a quad's front is drawn" {
    const shadings = [_]SurfShadingData{ColorShading(RED)};
    const shapes = [_]TestShape{MakeQuad(.{ .x = 0, .y = 0, .z = 0 }, IDENTITY, .{ .x = 1, .y = 1 }, 0, 0, SDFFunc.NO_CLIP)};
    const from_behind = Ray{ .Origin = .{ .x = 0, .y = 0, .z = -10 }, .Dir = .{ .x = 0, .y = 0, .z = 1 } };
    try ExpectColor(DEFAULT_COLOR, Trace(.{ .Shapes = &shapes, .Shadings = &shadings }, from_behind));
}

test "a quad past the far distance is not drawn" {
    const shadings = [_]SurfShadingData{ColorShading(RED)};
    const shapes = [_]TestShape{MakeQuad(.{ .x = 0, .y = 0, .z = -2 * FAR }, IDENTITY, .{ .x = 1, .y = 1 }, 0, 0, SDFFunc.NO_CLIP)};
    try ExpectColor(DEFAULT_COLOR, Trace(.{ .Shapes = &shapes, .Shadings = &shadings }, RayAt(0, 0)));
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
    try ExpectColor(DEFAULT_COLOR, Trace(.{ .Shapes = &shapes, .Shadings = &shadings }, grazing));
}

//==================================which shape is in front==================================

test "the nearer of two overlapping quads is drawn, whichever order they are in" {
    const shadings = [_]SurfShadingData{ ColorShading(RED), ColorShading(BLUE) };
    const near = MakeQuad(.{ .x = 0, .y = 0, .z = 1 }, IDENTITY, .{ .x = 1, .y = 1 }, 0, 0, SDFFunc.NO_CLIP);
    const far = MakeQuad(.{ .x = 0, .y = 0, .z = 0 }, IDENTITY, .{ .x = 1, .y = 1 }, 1, 0, SDFFunc.NO_CLIP);

    const near_first = [_]TestShape{ near, far };
    const far_first = [_]TestShape{ far, near };
    try ExpectColor(RED, Trace(.{ .Shapes = &near_first, .Shadings = &shadings }, RayAt(0, 0)));
    try ExpectColor(RED, Trace(.{ .Shapes = &far_first, .Shadings = &shadings }, RayAt(0, 0)));
}

//How exact ties come out today. Step 4 of the renderer plan picks a tie rule on purpose; if it changes these,
//change them with it rather than to make them pass
test "of two quads at the same depth, the first one in the buffer is drawn" {
    const shadings = [_]SurfShadingData{ ColorShading(RED), ColorShading(BLUE) };
    const shapes = [_]TestShape{
        MakeQuad(.{ .x = 0, .y = 0, .z = 0 }, IDENTITY, .{ .x = 1, .y = 1 }, 0, 0, SDFFunc.NO_CLIP),
        MakeQuad(.{ .x = 0, .y = 0, .z = 0 }, IDENTITY, .{ .x = 1, .y = 1 }, 1, 0, SDFFunc.NO_CLIP),
    };
    try ExpectColor(RED, Trace(.{ .Shapes = &shapes, .Shadings = &shadings }, RayAt(0, 0)));
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
    try ExpectColor(RED, Trace(.{ .Shapes = &quad_first, .Shadings = &shadings }, RayAt(-0.25, 0)));
    try ExpectColor(RED, Trace(.{ .Shapes = &glyph_first, .Shadings = &shadings }, RayAt(-0.25, 0)));
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
    try ExpectColor(.{ .x = 0.5, .y = 0, .z = 0.5, .w = 0.75 }, Trace(.{ .Shapes = &shapes, .Shadings = &shadings }, RayAt(0, 0)));
}

test "a see-through quad with nothing behind it blends with the default color" {
    const half_red = Vec4(f32){ .x = 1, .y = 0, .z = 0, .w = 0.5 };
    const shadings = [_]SurfShadingData{ColorShading(half_red)};
    const shapes = [_]TestShape{MakeQuad(.{ .x = 0, .y = 0, .z = 0 }, IDENTITY, .{ .x = 1, .y = 1 }, 0, TRANSPARENT, SDFFunc.NO_CLIP)};
    try ExpectColor(half_red.Lerp(DEFAULT_COLOR, 0.5), Trace(.{ .Shapes = &shapes, .Shadings = &shadings }, RayAt(0, 0)));
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
    try ExpectColor(half_red.Lerp(middle, 0.5), Trace(.{ .Shapes = &shapes, .Shadings = &shadings }, RayAt(0, 0)));
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
    try ExpectColor(.{ .x = 0.5, .y = 0, .z = 0.5, .w = 0.75 }, Trace(.{ .Shapes = &shapes, .Shadings = &shadings, .Mediums = &mediums }, RayAt(0, 0)));
}

test "a quad without the see-through flag hides what is behind it, even with a see-through color" {
    //its color still blends, but with the default color rather than the blue quad behind it
    const half_red = Vec4(f32){ .x = 1, .y = 0, .z = 0, .w = 0.5 };
    const shadings = [_]SurfShadingData{ ColorShading(half_red), ColorShading(BLUE) };
    const shapes = [_]TestShape{
        MakeQuad(.{ .x = 0, .y = 0, .z = 1 }, IDENTITY, .{ .x = 1, .y = 1 }, 0, 0, SDFFunc.NO_CLIP),
        MakeQuad(.{ .x = 0, .y = 0, .z = 0 }, IDENTITY, .{ .x = 1, .y = 1 }, 1, 0, SDFFunc.NO_CLIP),
    };
    try ExpectColor(half_red.Lerp(DEFAULT_COLOR, 0.5), Trace(.{ .Shapes = &shapes, .Shadings = &shadings }, RayAt(0, 0)));
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
    try ExpectColor(RED, Trace(scene, RayAt(-0.5, 0)));
    try ExpectColor(BLUE, Trace(scene, RayAt(0.5, 0)));
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
    try ExpectColor(GREEN, Trace(scene, RayAt(-0.25, 0)));
    try ExpectColor(BLUE, Trace(scene, RayAt(0.25, 0)));
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
    try ExpectColor(grey, Trace(.{ .Shapes = &shapes, .Shadings = &shadings }, RayAt(-0.25, 0)));
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
    try ExpectColor(.{ .x = 0.5, .y = 0, .z = 0.5, .w = 0.75 }, Trace(.{ .Shapes = &shapes, .Shadings = &shadings }, RayAt(-0.25, 0)));
}

//! The renderer's shapes made from the world's trees (Renderer.Fill), the overlay's in canvas units and looked
//! at from the camera as seen from the canvas, checked against making them the old way for one view (Renderer.FillView),
//! the overlay's placed in world space: every pixel traced through both on the CPU marcher has to come out the same
//! color. No window or GPU. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const WorldBVH = @import("../../Core/WorldBVH.zig");
const BVH = @import("../../Core/BVH.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const Renderer = @import("../../Renderer/Renderer.zig");
const Renderer2D = @import("../../Renderer/Renderer2D.zig");
const ShapeData = Renderer2D.ShapeData;
const ShapeSurface = Renderer2D.ShapeSurface;
const SDFProgram = @import("../../Renderer/SDFProgram.zig");
const SDFRayMarcher = @import("../../Renderer/SDFRayMarcher.zig");
const RenderStats = @import("../../Core/EngineStats.zig").RenderStats;
const PushConstants = @import("../../Renderer/RenderPipeline.zig").SDFPushConstants;
const ShapeGeometry = @import("../../Renderer/ShapeGeometry.zig");
const CameraRay = @import("../../Math/CameraRay.zig");
const MathTypes = @import("../../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;
const Vec3 = MathTypes.Vec3;
const Vec4 = MathTypes.Vec4;
const Quat = MathTypes.Quat;

const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const ShapeComponent = EntityComponents.ShapeComponent;
const SurfaceComponent = EntityComponents.SurfaceComponent;
const ColliderComponent = EntityComponents.ColliderComponent;
const MaskComponent = EntityComponents.MaskComponent;
const MergeComponent = EntityComponents.MergeComponent;
const LayoutHiddenTag = EntityComponents.LayoutHiddenTag;

const TestWorld = struct {
    mEngineContext: *EngineContext,

    fn Init() !*TestWorld {
        const self = try std.heap.page_allocator.create(TestWorld);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext) };
        const engine_context = self.mEngineContext;
        engine_context.* = .{};
        engine_context._Internal.ThreadedIO = std.Io.Threaded.init(engine_context._Internal.EngineGPA.allocator(), .{
            .concurrent_limit = .nothing,
            .async_limit = .nothing,
        });
        //drawing a quad looks up its texture, which with none set is the default one
        try engine_context.mAssetManager.Init(engine_context);
        try engine_context.mEditorWorld.Init(engine_context);
        return self;
    }

    fn Deinit(self: *TestWorld) void {
        const engine_context = self.mEngineContext;
        const engine_allocator = engine_context.EngineAllocator();
        engine_context.mEditorWorld.Deinit(engine_context);
        const asset_manager = &engine_context.mAssetManager;
        asset_manager.mECSManager.Deinit(engine_context);
        asset_manager.mUUIDToWorldID.deinit(engine_allocator);
        asset_manager.mEventManager.Deinit(engine_allocator);
        asset_manager.mCWDPath.deinit(engine_allocator);
        _ = engine_context._Internal.EngineGPA.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }
};

/// A renderer with only its CPU side used: nothing on it is set up for a GPU, and its lists are freed by FreeCPU
fn FreeCPU(renderer: *Renderer, engine_allocator: std.mem.Allocator) void {
    renderer.mR2D.mOverlayData.Reset(engine_allocator, .ClearAndFree);
    renderer.mR2D.mGameData.Reset(engine_allocator, .ClearAndFree);
    renderer.mR2D.mOverlayData.mMaskBufferBase.deinit(engine_allocator);
    renderer.mR2D.mGameData.mMaskBufferBase.deinit(engine_allocator);
    renderer.mR2D.mWarnedMerges.deinit(engine_allocator);
    renderer.mSDFShading.Reset(engine_allocator, .ClearAndFree);
    renderer.mShownCopies.deinit(engine_allocator);
}

//==================================the view and its rays==================================

const WIDTH: f32 = 1600;
const HEIGHT: f32 = 900;
const FOV: f32 = std.math.degreesToRadians(@as(f32, 60.0));
const FAR: f32 = 1000;

/// A little off the origin and turned, so nothing lines up with the axes by luck
const POSE = CameraRay.Pose{
    .Position = .{ .x = 0.3, .y = -0.2, .z = 1 },
    .Rotation = .{ .w = 0.9990482, .x = 0.0261769, .y = 0.0348995, .z = 0 },
};

const VIEW = Renderer.CameraView{ .Pose = POSE, .TanHalfFov = @tan(FOV / 2), .TargetWidth = WIDTH, .TargetHeight = HEIGHT, .FarDistance = FAR, .DisplayScale = 1 };

/// What a render through VIEW hands the renderer (Renderer.BuildPushConstants for a camera entity)
fn ViewPushConstants() PushConstants {
    const ray_params = CameraRay.ComputeRayParams(FOV, WIDTH, HEIGHT);
    return .{
        .mPosition = POSE.Position.ToArray(),
        .mRotation = POSE.Rotation.ToArray(),
        .mRayScale = ray_params.Scale.ToArray(),
        .mRayOffset = ray_params.Offset.ToArray(),
        .mPerspectiveFar = FAR,
        .mShapesCount = 0,
        .mDirectCount = 0,
        .mViewportWidth = WIDTH,
        .mViewportHeight = HEIGHT,
        .mFlags = 0,
        .mHeatMetric = 0,
        .mHeatRedAt = 1,
        .mMediumScale = 1,
    };
}

/// The ray a pass's shader traces through `pixel`, from its push constants, the way SDFComputeOverlay's main makes it
fn PassRay(push_constants: PushConstants, pixel: Vec2(f32)) CameraRay.Ray {
    const ray_params = CameraRay.RayParams{ .Scale = .FromArray(push_constants.mRayScale), .Offset = .FromArray(push_constants.mRayOffset) };
    return CameraRay.MakeRay(.{ .Position = .FromArray(push_constants.mPosition), .Rotation = .FromArray(push_constants.mRotation) }, ray_params, pixel);
}

//==================================tracing a pass on the CPU==================================

const FakeTextures = struct {};
const TEXTURES = FakeTextures{};

/// Every texture is plain white, so a surface is its color
fn FakeSample(_: *const FakeTextures, _: @Vector(3, f32), _: f32) @Vector(4, f32) {
    return .{ 1, 1, 1, 1 };
}

fn PassMarcher(comptime search: SDFRayMarcher.DirectSearch) type {
    return SDFRayMarcher.RayMarcher(
        [*]const ShapeData,
        [*]const ShapeSurface,
        [*]const BVH.Node,
        [*]const SDFProgram.MaskData,
        [*]const SDFProgram.Instr,
        [*]const SDFProgram.Part,
        [*]const Renderer.SurfShadingData,
        [*]const Renderer.MedShadingData,
        *const FakeTextures,
        search,
        .full,
    );
}

/// The color one pass of `renderer` draws at `pixel`: its shapes found by walking their tree (`search` .BVH) or by
/// testing them all (.Linear)
fn TracePass(renderer: *const Renderer, buffers: *const Renderer2D.RenderBuffers, push_constants: PushConstants, background: Vec4(f32), pixel: Vec2(f32), comptime search: SDFRayMarcher.DirectSearch) Vec4(f32) {
    const shapes = buffers.mShapeBufferBase.items;
    if (shapes.len == 0) return background;
    const shading = &renderer.mSDFShading;
    var marcher = PassMarcher(search){
        .mDefaultColor = background,
        .mShapes = shapes.ptr,
        .mShapeSurfaces = buffers.mSurfaceBufferBase.items.ptr,
        .mShapesCount = shapes.len,
        .mDirectCount = buffers.mDirectCount,
        .mBVHNodes = buffers.mBVHNodes.items.ptr,
        .mMasks = buffers.mMaskBufferBase.items.ptr,
        .mInstrs = buffers.mPrograms.mInstrs.items.ptr,
        .mParts = buffers.mPrograms.mParts.items.ptr,
        .mSurfShading = shading.mSurfShadingBuffBase.items.ptr,
        .mMedShading = shading.mMedShadingBuffBase.items.ptr,
        .mPerspectiveFar = push_constants.mPerspectiveFar,
        .mMediumScale = push_constants.mMediumScale,
    };
    marcher.Start(PassRay(push_constants, pixel));
    marcher.March(FakeSample, &TEXTURES);
    return marcher.GenerateColor(FakeSample, &TEXTURES);
}

const OVERLAY_BACKGROUND: Vec4(f32) = .FromArray(PushConstants.OVERLAY_BACKGROUND);
const GAME_BACKGROUND: Vec4(f32) = .FromArray(PushConstants.GAME_BACKGROUND);

fn Same(a: Vec4(f32), b: Vec4(f32)) bool {
    const tolerance: f32 = 0.002;
    return @abs(a.x - b.x) <= tolerance and @abs(a.y - b.y) <= tolerance and @abs(a.z - b.z) <= tolerance and @abs(a.w - b.w) <= tolerance;
}

const Covered = struct {
    Overlay: usize = 0,
    Game: usize = 0,
};

/// Fills a renderer each way for `view_scenes` and traces `pixels` random pixels through both passes of each: every
/// one has to come out the same color. How many pixels hit something in each layer, so a test can be sure it saw some
fn ExpectSamePictures(engine_context: *EngineContext, random: std.Random, view_scenes: Renderer.ViewScenes, show_colliders: bool, pixels: usize) !Covered {
    const world = &engine_context.mEditorWorld;
    const engine_allocator = engine_context.EngineAllocator();
    var stats: RenderStats = .{};

    var from_tree: Renderer = .{};
    defer FreeCPU(&from_tree, engine_allocator);
    from_tree.mShowColliders = show_colliders;
    try engine_context.mSystems.RunSystem(Renderer.Fill, engine_context, .{ &from_tree, world, view_scenes, VIEW, &stats });

    var one_view: Renderer = .{};
    defer FreeCPU(&one_view, engine_allocator);
    one_view.mShowColliders = show_colliders;
    try engine_context.mSystems.RunSystem(Renderer.FillView, engine_context, .{ &one_view, world, view_scenes, VIEW, &stats });

    const push_constants = ViewPushConstants();
    const tree_overlay = Renderer.OverlayPushConstants(push_constants, from_tree.mOverlayCanvas);
    const view_overlay = Renderer.OverlayPushConstants(push_constants, one_view.mOverlayCanvas);
    //the tree's overlay really is in other units, looked at from somewhere else
    try std.testing.expect(from_tree.mOverlayCanvas != null and one_view.mOverlayCanvas == null);

    var covered = Covered{};
    for (0..pixels) |_| {
        const pixel = Vec2(f32){ .x = random.float(f32) * WIDTH, .y = random.float(f32) * HEIGHT };

        const overlay = TracePass(&from_tree, &from_tree.mR2D.mOverlayData, tree_overlay, OVERLAY_BACKGROUND, pixel, .BVH);
        const overlay_expected = TracePass(&one_view, &one_view.mR2D.mOverlayData, view_overlay, OVERLAY_BACKGROUND, pixel, .Linear);
        if (!Same(overlay_expected, overlay)) {
            std.debug.print("overlay pass differs at pixel ({d}, {d}): from the tree {any}, one view {any}\n", .{ pixel.x, pixel.y, overlay, overlay_expected });
            return error.TestExpectedEqual;
        }
        if (!Same(OVERLAY_BACKGROUND, overlay)) covered.Overlay += 1;

        const game = TracePass(&from_tree, &from_tree.mR2D.mGameData, push_constants, GAME_BACKGROUND, pixel, .BVH);
        const game_expected = TracePass(&one_view, &one_view.mR2D.mGameData, push_constants, GAME_BACKGROUND, pixel, .Linear);
        if (!Same(game_expected, game)) {
            std.debug.print("game pass differs at pixel ({d}, {d}): from the tree {any}, one view {any}\n", .{ pixel.x, pixel.y, game, game_expected });
            return error.TestExpectedEqual;
        }
        if (!Same(GAME_BACKGROUND, game)) covered.Game += 1;
    }
    return covered;
}

//==================================building a world==================================

fn RandomIn(random: std.Random, low: f32, high: f32) f32 {
    return low + random.float(f32) * (high - low);
}

/// A colored quad on `entity`: turned a little about z, some rounded, bordered or see-through
fn RandomQuad(engine_context: *EngineContext, random: std.Random, entity: Entity, position: Vec3(f32), size: f32) !void {
    try entity.SetTranslation(engine_context, position);
    try entity.SetRotation(engine_context, (Vec3(f32){ .x = 0, .y = 0, .z = RandomIn(random, -0.6, 0.6) }).RadiansToQuat());
    var quad = ShapeComponent.MakeQuad(.{ .Size = .{ .x = size * RandomIn(random, 0.5, 2), .y = size * RandomIn(random, 0.5, 2) } });
    if (random.boolean()) quad.GetQuadMut().?.CornerRadii = .{ .x = size * 0.3, .y = size * 0.2, .z = 0, .w = size * 0.3 };
    _ = try entity.AddComponent(engine_context, quad);
    var surface = SurfaceComponent{};
    surface.mTexOptions.mColor = .{ .x = random.float(f32), .y = random.float(f32), .z = random.float(f32), .w = 1 };
    switch (random.uintLessThan(u8, 6)) {
        0 => {
            surface.mTexOptions.mIsTransparent = true;
            surface.mTexOptions.mColor.w = 0.5;
        },
        1 => {
            surface.mBorderWidth = size * 0.1;
            surface.mBorderColor = .{ .x = 1, .y = 1, .z = 0, .w = 1 };
        },
        //see-through all the way: clicked, never drawn
        2 => {
            surface.mTexOptions.mIsTransparent = true;
            surface.mTexOptions.mColor.w = 0;
        },
        else => {},
    }
    _ = try entity.AddComponent(engine_context, surface);
}

/// Two game scenes and two overlay scenes of quads, masks with quads inside and past them, a merge and colliders
const TestScenes = struct {
    Levels: [2]Scene,
    Huds: [2]Scene,
};

fn BuildScenes(engine_context: *EngineContext, random: std.Random) !TestScenes {
    const world = &engine_context.mEditorWorld;
    var scenes: TestScenes = undefined;
    for (&scenes.Levels) |*level| level.* = try world.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    for (&scenes.Huds) |*hud| hud.* = try world.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);

    for (scenes.Levels) |level| {
        for (0..40) |_| {
            const position = Vec3(f32){ .x = RandomIn(random, -5, 5), .y = RandomIn(random, -3, 3), .z = RandomIn(random, -20, -4) };
            if (random.uintLessThan(u8, 5) == 0) {
                const body = try level.CreateEntity(engine_context, Entity.DefaultConfig);
                try body.SetTranslation(engine_context, position);
                _ = try body.AddComponent(engine_context, ColliderComponent{ .mShape = if (random.boolean()) .Box else .Sphere });
            } else {
                try RandomQuad(engine_context, random, try level.CreateEntity(engine_context, Entity.DefaultConfig), position, 1);
            }
        }
        //a mask with quads under it, some reaching past its edge
        const region = try level.CreateEntity(engine_context, Entity.DefaultConfig);
        try RandomQuad(engine_context, random, region, .{ .x = 0, .y = 0, .z = -7 }, 2.5);
        _ = try region.AddComponent(engine_context, MaskComponent{});
        for (0..6) |_| try RandomQuad(engine_context, random, try region.CreateChild(engine_context, .Entity, Entity.DefaultConfig), .{ .x = RandomIn(random, -2, 2), .y = RandomIn(random, -1.5, 1.5), .z = 0.05 }, 0.8);
        //a merge of two quads
        const merge = try level.CreateEntity(engine_context, Entity.DefaultConfig);
        try merge.SetTranslation(engine_context, .{ .x = RandomIn(random, -3, 3), .y = RandomIn(random, -2, 2), .z = -10 });
        _ = try merge.AddComponent(engine_context, MergeComponent{});
        for ([_]f32{ -0.4, 0.4 }) |x| {
            const part = try merge.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
            try part.SetTranslation(engine_context, .{ .x = x, .y = 0, .z = 0 });
            _ = try part.AddComponent(engine_context, ShapeComponent.MakeQuad(.{ .Size = .{ .x = 1, .y = 1 } }));
            var surface = SurfaceComponent{};
            surface.mTexOptions.mColor = .{ .x = random.float(f32), .y = random.float(f32), .z = random.float(f32), .w = 1 };
            _ = try part.AddComponent(engine_context, surface);
        }
    }
    //canvas units, around the middle of the screen, each at a UI depth of its own (Widgets.DEPTH_STEP apart): two
    //see-through quads overlapping at exactly the same depth come out in whichever order rounding gives, which world
    //and canvas units round differently
    var depth: f32 = 0;
    for (scenes.Huds) |hud| {
        for (0..25) |_| {
            depth += 0.01;
            const position = Vec3(f32){ .x = RandomIn(random, -700, 700), .y = RandomIn(random, -400, 400), .z = depth };
            try RandomQuad(engine_context, random, try hud.CreateEntity(engine_context, Entity.DefaultConfig), position, 120);
        }
        //a scrolled list: a mask and rows, some cut off
        depth += 0.01;
        const list = try hud.CreateEntity(engine_context, Entity.DefaultConfig);
        try RandomQuad(engine_context, random, list, .{ .x = RandomIn(random, -300, 300), .y = RandomIn(random, -200, 200), .z = depth }, 200);
        _ = try list.AddComponent(engine_context, MaskComponent{});
        for (0..8) |row| {
            const row_depth = @as(f32, @floatFromInt(row + 1)) * 0.01;
            try RandomQuad(engine_context, random, try list.CreateChild(engine_context, .Entity, Entity.DefaultConfig), .{ .x = 0, .y = 150 - @as(f32, @floatFromInt(row)) * 45, .z = row_depth }, 60);
        }
        depth += 0.1;
    }
    return scenes;
}

//==================================tests==================================

test "the passes made from the world's trees draw what one view's gathered shapes draw, pixel for pixel" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    var prng = std.Random.DefaultPrng.init(0xD4A3);
    const random = prng.random();

    const scenes = try BuildScenes(engine_context, random);
    try engine_context.mEditorWorld.BuildBVH(engine_context);

    //every scene, then only some: a template preview's one scene, one player's HUD
    const everything = try ExpectSamePictures(engine_context, random, .{ .Overlays = &.{ scenes.Huds[0].mID, scenes.Huds[1].mID } }, false, 500);
    try std.testing.expect(everything.Overlay > 100);
    try std.testing.expect(everything.Game > 50);
    const some = try ExpectSamePictures(engine_context, random, .{ .Game = .{ .One = scenes.Levels[1].mID }, .Overlays = &.{scenes.Huds[0].mID} }, false, 400);
    try std.testing.expect(some.Overlay > 40);
    try std.testing.expect(some.Game > 20);
    _ = try ExpectSamePictures(engine_context, random, .{ .Game = .None, .Overlays = &.{scenes.Huds[1].mID} }, false, 200);
    //and with the colliders shown
    const shown = try ExpectSamePictures(engine_context, random, .{ .Overlays = &.{} }, true, 400);
    try std.testing.expect(shown.Game > 50);
}

test "a shape hidden or deleted after the tree was built isn't drawn, and the rest still are" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    var prng = std.Random.DefaultPrng.init(0x41DE);
    const random = prng.random();

    _ = try BuildScenes(engine_context, random);
    try engine_context.mEditorWorld.BuildBVH(engine_context);

    //a few of each folded away, switched off and deleted mid frame, while the tree still has them
    const quads = try engine_context.mEditorWorld.GetEntityGroup(engine_context.FrameAllocator(), .{ .Component = SurfaceComponent });
    for (quads.items, 0..) |entity_id, i| {
        const entity = engine_context.mEditorWorld.GetEntity(entity_id);
        if (entity.HasComponent(MaskComponent) or entity.GetComponent(@import("../../ECS/Components.zig").ChildComponent(Entity.Type)) != null) continue;
        switch (i % 7) {
            0 => _ = try entity.AddComponent(engine_context, LayoutHiddenTag{}),
            1 => entity.GetComponentMut(SurfaceComponent).?.mShouldRender = false,
            2 => try entity.Delete(engine_context),
            else => {},
        }
    }
    const covered = try ExpectSamePictures(engine_context, random, .{ .Overlays = &.{} }, false, 400);
    try std.testing.expect(covered.Game > 40);
}

test "a mask taken off after the tree was built stops cutting what is under it, though its items still name it" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    var prng = std.Random.DefaultPrng.init(0x3A5C);
    const random = prng.random();

    const scenes = try BuildScenes(engine_context, random);
    try engine_context.mEditorWorld.BuildBVH(engine_context);

    const masks = try engine_context.mEditorWorld.GetEntityGroup(engine_context.FrameAllocator(), .{ .Component = MaskComponent });
    try std.testing.expect(masks.items.len > 0);
    for (masks.items) |entity_id| try engine_context.mEditorWorld.GetEntity(entity_id).RemoveComponent(engine_context, MaskComponent);

    const covered = try ExpectSamePictures(engine_context, random, .{ .Overlays = &.{ scenes.Huds[0].mID, scenes.Huds[1].mID } }, false, 500);
    try std.testing.expect(covered.Overlay > 100);
    try std.testing.expect(covered.Game > 50);
}

test "a tree item's surface is put at its place before the build, so a tie at the same depth goes the same way however the tree is built" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const level = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    var prng = std.Random.DefaultPrng.init(0x7E5);
    const random = prng.random();
    for (0..30) |_| try RandomQuad(engine_context, random, try level.CreateEntity(engine_context, Entity.DefaultConfig), .{ .x = RandomIn(random, -5, 5), .y = RandomIn(random, -3, 3), .z = -6 }, 1);
    try engine_context.mEditorWorld.BuildBVH(engine_context);

    var stats: RenderStats = .{};
    var renderer: Renderer = .{};
    defer FreeCPU(&renderer, engine_context.EngineAllocator());
    try engine_context.mSystems.RunSystem(Renderer.Fill, engine_context, .{ &renderer, &engine_context.mEditorWorld, Renderer.ViewScenes{ .Overlays = &.{} }, VIEW, &stats });

    const tree = engine_context.mEditorWorld.mBVH.Tree(.GameLayer);
    for (renderer.mR2D.mGameData.mShapeBufferBase.items, tree.mItems.items) |shape, item| {
        try std.testing.expectEqual(item.Order, shape.SurfaceIndex);
    }
    //and the whole picture, every quad at one depth, matches the old way's draw order
    _ = try ExpectSamePictures(engine_context, random, .{ .Overlays = &.{} }, false, 300);
}

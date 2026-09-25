//! CastRay against a real world (no window, no renderer). Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const Scene = @import("../ECSObjects/Scene.zig");
const PhysicsManager = @import("PhysicsManager.zig");
const RayCast = @import("RayCast.zig");
const ShapeGeometry = @import("../Renderer/ShapeGeometry.zig");
const CameraView = @import("../Renderer/Renderer.zig").CameraView;
const CameraRay = @import("../Math/CameraRay.zig");
const OverlayCanvas = @import("../Math/OverlayCanvas.zig");
const THICKNESS_2D = @import("../Math/SDFFunctions.zig").THICKNESS_2D;

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const TransformComponent = EntityComponents.TransformComponent;
const QuadComponent = EntityComponents.QuadComponent;
const TextComponent = EntityComponents.TextComponent;
const ColliderComponent = EntityComponents.ColliderComponent;

const MathTypes = @import("../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;
const Vec3 = MathTypes.Vec3;
const Quat = MathTypes.Quat;

const eps: f32 = 0.001;

const TestWorld = struct {
    mEngineContext: *EngineContext,

    fn Init() !*TestWorld {
        const self = try std.heap.page_allocator.create(TestWorld);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext) };
        self.mEngineContext.* = .{};
        try self.mEngineContext.mEditorWorld.Init(self.mEngineContext.EngineAllocator());
        return self;
    }

    fn Deinit(self: *TestWorld) void {
        const engine_context = self.mEngineContext;
        engine_context.mEditorWorld.Deinit(engine_context);
        _ = engine_context._Internal.EngineGPA.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }
};

//a 1600x900 view with a 60 degree fov, like the editor's default viewpoint
const WIDTH: f32 = 1600;
const HEIGHT: f32 = 900;
const FOV: f32 = std.math.degreesToRadians(@as(f32, 60.0));

const ORIGIN_POSE = CameraRay.Pose{
    .Position = .{ .x = 0, .y = 0, .z = 0 },
    .Rotation = .{ .w = 1, .x = 0, .y = 0, .z = 0 },
};

fn View(pose: CameraRay.Pose) CameraView {
    return .{ .Pose = pose, .TanHalfFov = @tan(FOV / 2), .TargetHeight = HEIGHT, .FarDistance = 1000, .DisplayScale = 1 };
}

fn PixelRay(pose: CameraRay.Pose, pixel: Vec2(f32)) CameraRay.Ray {
    return CameraRay.MakeRay(pose, CameraRay.ComputeRayParams(FOV, WIDTH, HEIGHT), pixel);
}

fn CenterRay(pose: CameraRay.Pose) CameraRay.Ray {
    return PixelRay(pose, .{ .x = WIDTH / 2, .y = HEIGHT / 2 });
}

fn Cast(engine_context: *EngineContext, pose: CameraRay.Pose, ray: CameraRay.Ray, options: RayCast.CastOptions) !?RayCast.RayHit {
    return RayCast.CastRay(engine_context, &engine_context.mEditorWorld, ray, View(pose), options);
}

fn AddQuad(engine_context: *EngineContext, scene: Scene, position: Vec3(f32), size: Vec2(f32)) !Entity {
    const entity = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    try entity.SetTranslation(engine_context, position);
    _ = try entity.AddComponent(engine_context, QuadComponent{ .mSize = size });
    return entity;
}

fn AddCollider(engine_context: *EngineContext, scene: Scene, position: Vec3(f32), collider: ColliderComponent) !Entity {
    const entity = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    try entity.SetTranslation(engine_context, position);
    _ = try entity.AddComponent(engine_context, collider);
    return entity;
}

fn ExpectEntity(expected: Entity, hit: ?RayCast.RayHit) !void {
    const actual = hit orelse return error.TestExpectedHit;
    try std.testing.expectEqual(expected.mID, actual.Entity.mID);
}

test "the nearest game quad is hit" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const near = try AddQuad(engine_context, scene, .{ .x = 0, .y = 0, .z = -10 }, .{ .x = 4, .y = 4 });
    _ = try AddQuad(engine_context, scene, .{ .x = 0, .y = 0, .z = -20 }, .{ .x = 4, .y = 4 });
    try PhysicsManager.UpdateWorldTransforms(.Editor, engine_context);

    const hit = try Cast(engine_context, ORIGIN_POSE, CenterRay(ORIGIN_POSE), .{});
    try ExpectEntity(near, hit);
    //a quad is a box THICKNESS_2D thick, so its front face is that much nearer than its center
    try std.testing.expectApproxEqAbs(10 - THICKNESS_2D, hit.?.T, eps);
    try std.testing.expectEqual(RayCast.RayHitKind.Quad, hit.?.Kind);
    try std.testing.expectEqual(.GameLayer, hit.?.Layer);
}

test "an overlay quad wins over a nearer game quad" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    //the game quad is 5 away, the overlay canvas 100: nearer in 3D, but the overlay is drawn on top
    const game_scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    _ = try AddQuad(engine_context, game_scene, .{ .x = 0, .y = 0, .z = -5 }, .{ .x = 4, .y = 4 });
    const overlay_scene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    const overlay_quad = try AddQuad(engine_context, overlay_scene, .{ .x = 0, .y = 0, .z = 0 }, .{ .x = 100, .y = 100 });
    try PhysicsManager.UpdateWorldTransforms(.Editor, engine_context);

    const hit = try Cast(engine_context, ORIGIN_POSE, CenterRay(ORIGIN_POSE), .{});
    try ExpectEntity(overlay_quad, hit);
    try std.testing.expectEqual(.OverlayLayer, hit.?.Layer);
}

test "a hidden quad can't be hit" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const hidden = try AddQuad(engine_context, scene, .{ .x = 0, .y = 0, .z = -10 }, .{ .x = 4, .y = 4 });
    hidden.GetComponent(QuadComponent).?.mShouldRender = false;
    const behind = try AddQuad(engine_context, scene, .{ .x = 0, .y = 0, .z = -20 }, .{ .x = 4, .y = 4 });
    try PhysicsManager.UpdateWorldTransforms(.Editor, engine_context);

    try ExpectEntity(behind, try Cast(engine_context, ORIGIN_POSE, CenterRay(ORIGIN_POSE), .{}));
}

test "a quad past the far distance can't be hit" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    _ = try AddQuad(engine_context, scene, .{ .x = 0, .y = 0, .z = -2000 }, .{ .x = 400, .y = 400 });
    try PhysicsManager.UpdateWorldTransforms(.Editor, engine_context);

    try std.testing.expect(try Cast(engine_context, ORIGIN_POSE, CenterRay(ORIGIN_POSE), .{}) == null);
}

test "an overlay quad stays under the same pixel when the camera moves" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const overlay_scene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    const quad = try AddQuad(engine_context, overlay_scene, .{ .x = 300, .y = 200, .z = 0 }, .{ .x = 40, .y = 40 });
    try PhysicsManager.UpdateWorldTransforms(.Editor, engine_context);

    //scale with screen at 900 tall: 900 / 1080 pixels per canvas unit
    const k = OverlayCanvas.PixelsPerUnit(.ScaleWithScreen, HEIGHT, 1);
    const on_quad = Vec2(f32){ .x = WIDTH / 2 + 300 * k, .y = HEIGHT / 2 - 200 * k };
    const beside_quad = Vec2(f32){ .x = on_quad.x + 60 * k, .y = on_quad.y };

    const yaw = Quat(f32).FromAxisAngle(.{ .x = 0, .y = 1, .z = 0 }, std.math.degreesToRadians(@as(f32, 70.0)));
    const moved_pose = CameraRay.Pose{ .Position = .{ .x = 40, .y = -12, .z = 7 }, .Rotation = yaw };

    for ([_]CameraRay.Pose{ ORIGIN_POSE, moved_pose }) |pose| {
        try ExpectEntity(quad, try Cast(engine_context, pose, PixelRay(pose, on_quad), .{}));
        try std.testing.expect(try Cast(engine_context, pose, PixelRay(pose, beside_quad), .{}) == null);
    }
}

test "colliders are only hit when asked for" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const sphere = try AddCollider(engine_context, scene, .{ .x = 0, .y = 0, .z = -10 }, .{ .mShape = .Sphere, .mRadius = 0.5 });
    try PhysicsManager.UpdateWorldTransforms(.Editor, engine_context);

    //nothing is drawn there, so a visuals cast goes straight through
    try std.testing.expect(try Cast(engine_context, ORIGIN_POSE, CenterRay(ORIGIN_POSE), .{}) == null);

    const hit = try Cast(engine_context, ORIGIN_POSE, CenterRay(ORIGIN_POSE), .{ .Targets = .Colliders });
    try ExpectEntity(sphere, hit);
    try std.testing.expectApproxEqAbs(@as(f32, 9.5), hit.?.T, eps);
    try std.testing.expectEqual(RayCast.RayHitKind.Collider, hit.?.Kind);
}

test "box colliders are hit as the rotated box" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    //2 wide and deep, turned 45 degrees: the ray meets the corner edge sqrt(2) in front of the center,
    //where an unturned box would be hit 1 in front
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const box = try AddCollider(engine_context, scene, .{ .x = 0, .y = 0, .z = -10 }, .{ .mShape = .Box, .mBoxSize = .{ .x = 2, .y = 1, .z = 2 } });
    try box.SetRotation(engine_context, Quat(f32).FromAxisAngle(.{ .x = 0, .y = 1, .z = 0 }, std.math.degreesToRadians(@as(f32, 45.0))));
    try PhysicsManager.UpdateWorldTransforms(.Editor, engine_context);

    const hit = try Cast(engine_context, ORIGIN_POSE, CenterRay(ORIGIN_POSE), .{ .Targets = .Colliders });
    try ExpectEntity(box, hit);
    try std.testing.expectApproxEqAbs(10 - std.math.sqrt2, hit.?.T, eps);
}

test "a ray starting inside a collider only hits it when asked to" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const around = try AddCollider(engine_context, scene, .{ .x = 0, .y = 0, .z = 0 }, .{ .mShape = .Box, .mBoxSize = .{ .x = 4, .y = 4, .z = 4 } });
    try PhysicsManager.UpdateWorldTransforms(.Editor, engine_context);

    try std.testing.expect(try Cast(engine_context, ORIGIN_POSE, CenterRay(ORIGIN_POSE), .{ .Targets = .Colliders }) == null);

    const hit = try Cast(engine_context, ORIGIN_POSE, CenterRay(ORIGIN_POSE), .{ .Targets = .Colliders, .SkipStartedInside = false });
    try ExpectEntity(around, hit);
    try std.testing.expect(hit.?.StartedInside);
    try std.testing.expectEqual(@as(f32, 0), hit.?.T);
}

test "nothing under the ray is no hit" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    _ = try AddQuad(engine_context, scene, .{ .x = 50, .y = 0, .z = -10 }, .{ .x = 4, .y = 4 });
    try PhysicsManager.UpdateWorldTransforms(.Editor, engine_context);

    try std.testing.expect(try Cast(engine_context, ORIGIN_POSE, CenterRay(ORIGIN_POSE), .{}) == null);
}

//a font with a single glyph, just enough for TextLayout to measure lines with
const FakeFont = struct {
    const Glyph = struct {
        mAtlasTexel0: Vec2(f32) = .{ .x = 0, .y = 1 },
        mAtlasTexel1: Vec2(f32) = .{ .x = 1, .y = 0 },
        mPlaneMin: Vec2(f32) = .{ .x = 0, .y = 0.7 },
        mPlaneMax: Vec2(f32) = .{ .x = 0.5, .y = 0 },
        mAdvance: f32 = 0.5,
        mKernings: std.AutoHashMap(u16, f32),
    };

    mGlyphs: [1]Glyph,
    mLineHeight: f32 = 1.2,
    mAscender: f32 = 0.9,
    mDescender: f32 = -0.2,
    mAtlasSize: Vec2(f32) = .{ .x = 1, .y = 1 },

    pub fn ToArrayIndex(_: usize) usize {
        return 0;
    }
};

test "text is hit over its whole bounds area, not just its letters" {
    var font = FakeFont{ .mGlyphs = .{.{ .mKernings = std.AutoHashMap(u16, f32).init(std.testing.allocator) }} };
    defer font.mGlyphs[0].mKernings.deinit();

    //one short line: a single glyph 0.5 * 2 = 1 wide, inside bounds that run 5 left and 5 right
    var text: TextComponent = .{ .mFontSize = 2, .mBounds = .{ .x = 5, .y = 5 } };
    try text.mText.appendSlice(std.testing.allocator, "A");
    defer text.mText.deinit(std.testing.allocator);

    var transform: TransformComponent = .{};
    transform.SetWorldPosition(.{ .x = 0, .y = 0, .z = -10 });

    const box = ShapeGeometry.TextBox(FakeFont, &transform, &text, &font, null);
    //the full width of the bounds, centered on the transform because they're even on both sides
    try std.testing.expectApproxEqAbs(@as(f32, 5), box.HalfExtents.x, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 0), box.Center.x, eps);
    //height from the ascender down to the descender of the one line, at font size 2
    try std.testing.expectApproxEqAbs(@as(f32, 0.9 + 0.2), box.HalfExtents.y, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 0.9 - 0.2), box.Center.y, eps);

    //scaling the text grows the whole area with it
    transform.SetWorldScale(.{ .x = 2, .y = 2, .z = 2 });
    const scaled = ShapeGeometry.TextBox(FakeFont, &transform, &text, &font, null);
    try std.testing.expectApproxEqAbs(@as(f32, 10), scaled.HalfExtents.x, eps);
}

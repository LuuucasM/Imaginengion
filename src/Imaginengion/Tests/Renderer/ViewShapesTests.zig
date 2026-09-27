//! GatherViewShapes: what one view shows, the list both the renderer and picking work from. No window or
//! renderer needed. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const ShapeGeometry = @import("../../Renderer/ShapeGeometry.zig");
const CameraView = @import("../../Renderer/Renderer.zig").CameraView;
const OverlayCanvas = @import("../../Math/OverlayCanvas.zig");

const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const QuadComponent = EntityComponents.QuadComponent;
const ColliderComponent = EntityComponents.ColliderComponent;
const LayoutHiddenTag = EntityComponents.LayoutHiddenTag;
const SceneComponent = @import("../../ECSComponents/SComponents.zig").SceneComponent;

const SEventData = @import("../../Events/SManagerData.zig");
const EEventData = @import("../../Events/EManagerData.zig");
const ECSEventData = @import("../../Events/ECSEventData.zig");

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

    /// EditorProgram.OnUpdate's end of frame for the editor world, where deletes happen
    fn EndFrame(self: *TestWorld) !void {
        const engine_context = self.mEngineContext;
        const world = &engine_context.mEditorWorld;
        var callback_list: std.DoublyLinkedList = .{};
        try world.ProcessEvents(SEventData, .EndOfFrame, engine_context, &callback_list);
        try world.ProcessEvents(EEventData, .EndOfFrame, engine_context, &callback_list);
        try world.ProcessEvents(ECSEventData, .EndOfFrame, engine_context, &callback_list);
    }
};

//a 900 tall view with a 60 degree fov on a display scaled 2x
const HEIGHT: f32 = 900;
const DISPLAY_SCALE: f32 = 2;
const VIEW = CameraView{
    .Pose = .{ .Position = .{ .x = 0, .y = 0, .z = 0 }, .Rotation = .{ .w = 1, .x = 0, .y = 0, .z = 0 } },
    .TanHalfFov = 0.57735, //tan(30 degrees)
    .TargetWidth = 1600,
    .TargetHeight = HEIGHT,
    .FarDistance = 1000,
    .DisplayScale = DISPLAY_SCALE,
};

fn AddQuad(engine_context: *EngineContext, scene: Scene) !Entity {
    const entity = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try entity.AddComponent(engine_context, QuadComponent{});
    return entity;
}

fn Gather(engine_context: *EngineContext, view_scenes: ShapeGeometry.ViewScenes) ![]const ShapeGeometry.ViewShape {
    const shapes = try ShapeGeometry.GatherViewShapes(engine_context.FrameAllocator(), &engine_context.mEditorWorld, VIEW, view_scenes, ShapeGeometry.VISUALS_QUERY);
    return shapes.items;
}

fn Contains(shapes: []const ShapeGeometry.ViewShape, entity: Entity) bool {
    for (shapes) |shape| {
        if (shape.Entity.mID == entity.mID) return true;
    }
    return false;
}

test "overlay shapes come first with their canvas, then the game layer's with none" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const level = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const hud = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    //made game first, so the order isn't just the order they were created in
    const rock = try AddQuad(engine_context, level);
    const tree = try AddQuad(engine_context, level);
    const button = try AddQuad(engine_context, hud);
    const label = try AddQuad(engine_context, hud);

    const shapes = try Gather(engine_context, .{ .Overlays = &.{hud.mID} });

    try std.testing.expectEqual(@as(usize, 4), shapes.len);
    try std.testing.expect(shapes[0].Canvas != null and shapes[1].Canvas != null);
    try std.testing.expect(shapes[2].Canvas == null and shapes[3].Canvas == null);
    for ([_]Entity{ rock, tree, button, label }) |entity| {
        try std.testing.expect(Contains(shapes, entity));
    }
    try std.testing.expect(!Contains(shapes[2..], button) and !Contains(shapes[2..], label));
}

test "an overlay the view doesn't list is left out" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const mine = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    const theirs = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    const my_button = try AddQuad(engine_context, mine);
    const their_button = try AddQuad(engine_context, theirs);

    const shapes = try Gather(engine_context, .{ .Overlays = &.{mine.mID} });
    try std.testing.expect(Contains(shapes, my_button));
    try std.testing.expect(!Contains(shapes, their_button));

    try std.testing.expectEqual(@as(usize, 0), (try Gather(engine_context, .{ .Overlays = &.{} })).len);
}

test "the game layer can be the whole world, one scene or none" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const level = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const other = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const rock = try AddQuad(engine_context, level);
    const tree = try AddQuad(engine_context, other);

    const all = try Gather(engine_context, .{ .Game = .All, .Overlays = &.{} });
    try std.testing.expect(Contains(all, rock) and Contains(all, tree));

    const one = try Gather(engine_context, .{ .Game = .{ .One = level.mID }, .Overlays = &.{} });
    try std.testing.expectEqual(@as(usize, 1), one.len);
    try std.testing.expect(Contains(one, rock));

    try std.testing.expectEqual(@as(usize, 0), (try Gather(engine_context, .{ .Game = .None, .Overlays = &.{} })).len);
}

test "each overlay scene gets the canvas of its own scale mode" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const hud = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    hud.GetComponent(SceneComponent).?.mOverlayScaleMode = .ScaleWithScreen;
    const tools = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    tools.GetComponent(SceneComponent).?.mOverlayScaleMode = .ConstantPixelSize;
    const health = try AddQuad(engine_context, hud);
    const gizmo = try AddQuad(engine_context, tools);

    const shapes = try Gather(engine_context, .{ .Overlays = &.{ hud.mID, tools.mID } });

    for (shapes) |shape| {
        const scene = if (shape.Entity.mID == health.mID) hud else if (shape.Entity.mID == gizmo.mID) tools else unreachable;
        const expected = ShapeGeometry.SceneCanvas(scene, VIEW);
        try std.testing.expectEqual(expected.Scale, shape.Canvas.?.Scale);
    }

    //a canvas unit is k pixels, so the canvases are scaled apart by the ratio of their pixels per unit
    const hud_k = OverlayCanvas.PixelsPerUnit(.ScaleWithScreen, HEIGHT, DISPLAY_SCALE);
    const tools_k = OverlayCanvas.PixelsPerUnit(.ConstantPixelSize, HEIGHT, DISPLAY_SCALE);
    const ratio = ShapeGeometry.SceneCanvas(hud, VIEW).Scale / ShapeGeometry.SceneCanvas(tools, VIEW).Scale;
    try std.testing.expectApproxEqRel(hud_k / tools_k, ratio, 0.0001);
}

test "only entities matching the query are gathered" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const level = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const rock = try AddQuad(engine_context, level);
    const wall = try level.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try wall.AddComponent(engine_context, ColliderComponent{});
    //nothing to draw or collide with
    const empty = try level.CreateEntity(engine_context, Entity.DefaultConfig);

    const visuals = try Gather(engine_context, .{ .Overlays = &.{} });
    try std.testing.expect(Contains(visuals, rock) and !Contains(visuals, wall) and !Contains(visuals, empty));

    const colliders = try ShapeGeometry.GatherViewShapes(engine_context.FrameAllocator(), &engine_context.mEditorWorld, VIEW, .{ .Overlays = &.{} }, .{ .Component = ColliderComponent });
    try std.testing.expectEqual(@as(usize, 1), colliders.items.len);
    try std.testing.expectEqual(wall.mID, colliders.items[0].Entity.mID);
}

test "an overlay scene that is gone, or isn't an overlay, is skipped" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const level = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const hud = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    const rock = try AddQuad(engine_context, level);
    _ = try AddQuad(engine_context, hud);
    const hud_id = hud.mID;

    //a game scene passed as an overlay isn't drawn a second time, through a canvas
    const shapes = try Gather(engine_context, .{ .Game = .None, .Overlays = &.{level.mID} });
    try std.testing.expect(!Contains(shapes, rock));

    try hud.Delete(engine_context);
    try world.EndFrame();
    try std.testing.expectEqual(@as(usize, 0), (try Gather(engine_context, .{ .Game = .None, .Overlays = &.{hud_id} })).len);
}

test "an entity folded away by a collapsed layout item is left out" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const hud = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    const level = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const shown = try AddQuad(engine_context, hud);
    const folded = try AddQuad(engine_context, hud);
    const folded_in_world = try AddQuad(engine_context, level);
    _ = try folded.AddComponent(engine_context, LayoutHiddenTag{});
    _ = try folded_in_world.AddComponent(engine_context, LayoutHiddenTag{});

    const shapes = try Gather(engine_context, .{ .Overlays = &.{hud.mID} });
    try std.testing.expect(Contains(shapes, shown));
    try std.testing.expect(!Contains(shapes, folded));
    try std.testing.expect(!Contains(shapes, folded_in_world));
}

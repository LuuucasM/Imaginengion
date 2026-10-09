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
const ShapeComponent = EntityComponents.ShapeComponent;
const SurfaceComponent = EntityComponents.SurfaceComponent;
const ColliderComponent = EntityComponents.ColliderComponent;
const LayoutHiddenTag = EntityComponents.LayoutHiddenTag;
const MaskComponent = EntityComponents.MaskComponent;
const NO_MASK = @import("../../Renderer/SDFProgram.zig").NO_MASK;
const PhysicsManager = @import("../../Physics/PhysicsManager.zig");
const MathTypes = @import("../../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;
const Vec3 = MathTypes.Vec3;
const Quat = MathTypes.Quat;
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
    _ = try entity.AddComponent(engine_context, ShapeComponent{});
    _ = try entity.AddComponent(engine_context, SurfaceComponent{});
    return entity;
}

fn GatherView(engine_context: *EngineContext, view_scenes: ShapeGeometry.ViewScenes) !ShapeGeometry.ViewShapes {
    return ShapeGeometry.GatherViewShapes(engine_context.FrameAllocator(), &engine_context.mEditorWorld, VIEW, view_scenes, ShapeGeometry.VISUALS_QUERY);
}

fn Gather(engine_context: *EngineContext, view_scenes: ShapeGeometry.ViewScenes) ![]const ShapeGeometry.ViewShape {
    return (try GatherView(engine_context, view_scenes)).Shapes.items;
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

test "every overlay scene of a world is on the world's one canvas" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const hud = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    const tools = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    _ = try AddQuad(engine_context, hud);
    _ = try AddQuad(engine_context, tools);

    const shapes = try Gather(engine_context, .{ .Overlays = &.{ hud.mID, tools.mID } });
    try std.testing.expectEqual(@as(usize, 2), shapes.len);
    const expected = ShapeGeometry.WorldCanvas(&engine_context.mEditorWorld, VIEW);
    for (shapes) |shape| {
        try std.testing.expectEqual(expected.Scale, shape.Canvas.?.Scale);
        try std.testing.expect(expected.Position.x == shape.Canvas.?.Position.x and expected.Position.y == shape.Canvas.?.Position.y and expected.Position.z == shape.Canvas.?.Position.z);
    }
}

test "the world's scale mode decides how big its canvas unit is" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const editor_world = &engine_context.mEditorWorld;

    editor_world.mOverlayScaleMode = .ScaleWithScreen;
    const scaled = ShapeGeometry.WorldCanvas(editor_world, VIEW).Scale;
    editor_world.mOverlayScaleMode = .ConstantPixelSize;
    const constant = ShapeGeometry.WorldCanvas(editor_world, VIEW).Scale;

    //a canvas unit is k pixels, so the canvases are scaled apart by the ratio of their pixels per unit
    const scaled_k = OverlayCanvas.PixelsPerUnit(.ScaleWithScreen, HEIGHT, DISPLAY_SCALE);
    const constant_k = OverlayCanvas.PixelsPerUnit(.ConstantPixelSize, HEIGHT, DISPLAY_SCALE);
    try std.testing.expectApproxEqRel(scaled_k / constant_k, scaled / constant, 0.0001);
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
    try std.testing.expectEqual(@as(usize, 1), colliders.Shapes.items.len);
    try std.testing.expectEqual(wall.mID, colliders.Shapes.items[0].Entity.mID);
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

//------------------------------clipping------------------------------

fn Find(shapes: []const ShapeGeometry.ViewShape, entity: Entity) ShapeGeometry.ViewShape {
    for (shapes) |shape| {
        if (shape.Entity.mID == entity.mID) return shape;
    }
    unreachable;
}

fn QuadAt(engine_context: *EngineContext, parent: Entity, position: Vec3(f32), size: Vec2(f32)) !Entity {
    const entity = try parent.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
    try entity.SetTranslation(engine_context, position);
    _ = try entity.AddComponent(engine_context, ShapeComponent.MakeQuad(.{ .Size = size }));
    _ = try entity.AddComponent(engine_context, SurfaceComponent{});
    return entity;
}

fn At(x: f32, y: f32, z: f32) Vec3(f32) {
    return .{ .x = x, .y = y, .z = z };
}

test "everything under a mask is cut by it, through any depth, the mask itself isn't" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const level = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    //a 4 x 2 mask at (10, 0), a child in it and a grandchild under that, and a quad outside it
    const region = try AddQuad(engine_context, level);
    try region.SetTranslation(engine_context, .{ .x = 10, .y = 0, .z = 0 });
    region.GetComponent(ShapeComponent).?.GetQuad().?.Size = .{ .x = 4, .y = 2 };
    _ = try region.AddComponent(engine_context, MaskComponent{});
    const child = try QuadAt(engine_context, region, .{ .x = 0, .y = 0, .z = 1 }, .{ .x = 10, .y = 10 });
    const grandchild = try QuadAt(engine_context, child, .{ .x = 0, .y = 0, .z = 0 }, .{ .x = 1, .y = 1 });
    const outside = try AddQuad(engine_context, level);
    try PhysicsManager.UpdateWorldTransforms(&engine_context.mEditorWorld, engine_context);

    const view = try GatherView(engine_context, .{ .Overlays = &.{} });
    const shapes = view.Shapes.items;
    try std.testing.expectEqual(NO_MASK, Find(shapes, region).Mask);
    try std.testing.expectEqual(NO_MASK, Find(shapes, outside).Mask);
    //one mask, shared
    try std.testing.expectEqual(@as(usize, 1), view.Masks.mMasks.items.len);
    const mask = Find(shapes, child).Mask;
    try std.testing.expectEqual(mask, Find(shapes, grandchild).Mask);
    try std.testing.expect(view.Masks.Contains(mask, At(11, 0.5, 0)));
    try std.testing.expect(view.Masks.Contains(mask, At(11, 0.5, 50)));
    try std.testing.expect(view.Masks.Contains(mask, At(9, -0.5, -50)));
    try std.testing.expect(!view.Masks.Contains(mask, At(12.5, 0, 0)));
    try std.testing.expect(!view.Masks.Contains(mask, At(10, 1.5, 0)));
}

test "a mask inside another is cut by both, and an overlay's is placed by its canvas" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const level = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    //x from 8 to 12, and inside it one from 9 to 13 and taller: what is kept is 9 to 12, the outer's height
    const outer = try AddQuad(engine_context, level);
    try outer.SetTranslation(engine_context, .{ .x = 10, .y = 0, .z = 0 });
    outer.GetComponent(ShapeComponent).?.GetQuad().?.Size = .{ .x = 4, .y = 2 };
    _ = try outer.AddComponent(engine_context, MaskComponent{});
    const inner = try QuadAt(engine_context, outer, .{ .x = 1, .y = 0, .z = 0 }, .{ .x = 4, .y = 4 });
    _ = try inner.AddComponent(engine_context, MaskComponent{});
    const deep = try QuadAt(engine_context, inner, .{ .x = 0, .y = 0, .z = 0 }, .{ .x = 1, .y = 1 });

    const hud = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    const panel = try AddQuad(engine_context, hud);
    try panel.SetTranslation(engine_context, .{ .x = 100, .y = 50, .z = 0 });
    panel.GetComponent(ShapeComponent).?.GetQuad().?.Size = .{ .x = 200, .y = 100 };
    _ = try panel.AddComponent(engine_context, MaskComponent{});
    const row = try QuadAt(engine_context, panel, .{ .x = 0, .y = 0, .z = 0 }, .{ .x = 10, .y = 10 });
    try PhysicsManager.UpdateWorldTransforms(&engine_context.mEditorWorld, engine_context);

    const view = try GatherView(engine_context, .{ .Overlays = &.{hud.mID} });
    const shapes = view.Shapes.items;
    const deep_mask = Find(shapes, deep).Mask;
    try std.testing.expectEqual(Find(shapes, inner).Mask, view.Masks.mMasks.items[deep_mask].Parent);
    try std.testing.expect(view.Masks.Contains(deep_mask, At(10.5, 0, 0)));
    //cut by the inner one, then by the outer one
    try std.testing.expect(!view.Masks.Contains(deep_mask, At(8.5, 0, 0)));
    try std.testing.expect(!view.Masks.Contains(deep_mask, At(12.5, 0, 0)));
    try std.testing.expect(!view.Masks.Contains(deep_mask, At(10.5, 1.5, 0)));

    const canvas = ShapeGeometry.WorldCanvas(hud.mManager, VIEW);
    const row_mask = Find(shapes, row).Mask;
    try std.testing.expect(view.Masks.Contains(row_mask, canvas.ToWorldPoint(At(190, 50, 0))));
    try std.testing.expect(!view.Masks.Contains(row_mask, canvas.ToWorldPoint(At(210, 50, 0))));
}

test "a subtract mask keeps what is outside it, and a mask with no shape leaves things to the one around it" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const level = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    //a 2 x 2 hole, and under it a mask with no shape
    const hole = try AddQuad(engine_context, level);
    hole.GetComponent(ShapeComponent).?.GetQuad().?.Size = .{ .x = 2, .y = 2 };
    _ = try hole.AddComponent(engine_context, MaskComponent{ .mOp = .Subtract });
    const shapeless = try hole.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
    _ = try shapeless.AddComponent(engine_context, MaskComponent{});
    const holed = try QuadAt(engine_context, shapeless, .{ .x = 0, .y = 0, .z = 0 }, .{ .x = 10, .y = 10 });
    try PhysicsManager.UpdateWorldTransforms(&engine_context.mEditorWorld, engine_context);

    const view = try GatherView(engine_context, .{ .Overlays = &.{} });
    const mask = Find(view.Shapes.items, holed).Mask;
    try std.testing.expectEqual(@as(usize, 1), view.Masks.mMasks.items.len);
    try std.testing.expect(!view.Masks.Contains(mask, At(0.5, 0, 0)));
    try std.testing.expect(view.Masks.Contains(mask, At(2, 0, 0)));
    //a subtract mask can't cut a whole shape off, however far away it is
    const far = ShapeGeometry.Box{ .Center = At(50, 0, 0), .Rotation = .{ .w = 1, .x = 0, .y = 0, .z = 0 }, .HalfExtents = At(1, 1, 0.001) };
    try std.testing.expect(!view.Masks.CutsOff(mask, far));
}

test "a box is only cut off by a mask's quad when none of it reaches into it, through any depth" {
    const identity = Quat(f32){ .w = 1, .x = 0, .y = 0, .z = 0 };
    const Box = ShapeGeometry.Box;
    const mask = Box{ .Center = .{ .x = 0, .y = 0, .z = 0 }, .Rotation = identity, .HalfExtents = .{ .x = 2, .y = 1, .z = 0.001 } };

    try std.testing.expect(ShapeGeometry.OutsideMaskBox(Box{ .Center = .{ .x = 4, .y = 0, .z = 0 }, .Rotation = identity, .HalfExtents = .{ .x = 1, .y = 1, .z = 0.001 } }, mask));
    //just reaching over the edge
    try std.testing.expect(!ShapeGeometry.OutsideMaskBox(Box{ .Center = .{ .x = 2.9, .y = 0, .z = 0 }, .Rotation = identity, .HalfExtents = .{ .x = 1, .y = 1, .z = 0.001 } }, mask));
    //far in front, but over it
    try std.testing.expect(!ShapeGeometry.OutsideMaskBox(Box{ .Center = .{ .x = 0, .y = 0, .z = 30 }, .Rotation = identity, .HalfExtents = .{ .x = 1, .y = 1, .z = 0.001 } }, mask));
    //a quarter turn makes a 1 x 3 box 3 tall: it reaches down into it from above
    const quarter = Quat(f32){ .w = std.math.sqrt1_2, .x = 0, .y = 0, .z = std.math.sqrt1_2 };
    try std.testing.expect(!ShapeGeometry.OutsideMaskBox(Box{ .Center = .{ .x = 0, .y = 3.5, .z = 0 }, .Rotation = quarter, .HalfExtents = .{ .x = 3, .y = 0.5, .z = 0.001 } }, mask));
    try std.testing.expect(ShapeGeometry.OutsideMaskBox(Box{ .Center = .{ .x = 0, .y = 3.5, .z = 0 }, .Rotation = identity, .HalfExtents = .{ .x = 3, .y = 0.5, .z = 0.001 } }, mask));
}

test "a viewport quad covers its size times the pixels a canvas unit covers, and only an overlay's has a size" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const Viewports = @import("../../Renderer/Viewports.zig");
    //sizing a player needs a GPU texture, so it is only checked to build here
    _ = &Viewports.FitPlayerToQuad;

    const overlay = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    const viewport = try AddQuad(engine_context, overlay);
    viewport.GetComponent(ShapeComponent).?.GetQuad().?.Size = .{ .x = 400, .y = 225 };

    //a constant pixel size world's overlay: a canvas unit is a pixel at the display's scale
    engine_context.mEditorWorld.mOverlayScaleMode = .ConstantPixelSize;
    const sharp = Viewports.PixelSizeOf(viewport, VIEW).?;
    try std.testing.expectEqual(@as(usize, 800), sharp.Width);
    try std.testing.expectEqual(@as(usize, 450), sharp.Height);

    //one that scales with the screen: a 900 tall view is 900 / 1080 of a pixel a unit
    engine_context.mEditorWorld.mOverlayScaleMode = .ScaleWithScreen;
    const scaled = Viewports.PixelSizeOf(viewport, VIEW).?;
    try std.testing.expectEqual(@as(usize, 333), scaled.Width);
    try std.testing.expectEqual(@as(usize, 188), scaled.Height);

    const game = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    try std.testing.expect(Viewports.PixelSizeOf(try AddQuad(engine_context, game), VIEW) == null);
}

/// The ray from VIEW's camera through a point of an overlay scene's canvas
fn RayThroughCanvas(scene: Scene, canvas_point: Vec3(f32)) @import("../../Math/CameraRay.zig").Ray {
    const world_point = ShapeGeometry.WorldCanvas(scene.mManager, VIEW).ToWorldPoint(canvas_point);
    var dir = world_point.SubVec(VIEW.Pose.Position);
    dir.Normalize();
    return .{ .Origin = VIEW.Pose.Position, .Dir = dir };
}

test "a ray through a viewport quad lands on the pixel of the picture under it, top left first, and off it only when allowed" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const Viewports = @import("../../Renderer/Viewports.zig");

    //400 x 200 canvas units, centered at (100, 50), showing an 800 x 400 picture
    const overlay = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    const quad = try AddQuad(engine_context, overlay);
    quad.GetComponent(ShapeComponent).?.GetQuad().?.Size = .{ .x = 400, .y = 200 };
    try quad.SetTranslation(engine_context, .{ .x = 100, .y = 50, .z = 0 });
    try PhysicsManager.UpdateWorldTransforms(&engine_context.mEditorWorld, engine_context);
    const picture = Vec2(f32){ .x = 800, .y = 400 };

    const center = Viewports.QuadPixelOnRay(quad, RayThroughCanvas(overlay, .{ .x = 100, .y = 50, .z = 0 }), VIEW, picture, .OnView).?;
    try std.testing.expectApproxEqAbs(@as(f32, 400), center.x, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 200), center.y, 0.5);

    //canvas y is up, so the quad's top left is the picture's first pixel
    const top_left = Viewports.QuadPixelOnRay(quad, RayThroughCanvas(overlay, .{ .x = -99, .y = 149, .z = 0 }), VIEW, picture, .OnView).?;
    try std.testing.expectApproxEqAbs(@as(f32, 2), top_left.x, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 2), top_left.y, 0.5);

    //past the right edge: nothing under the pointer, but a drag can still follow it there
    const past = RayThroughCanvas(overlay, .{ .x = 350, .y = 50, .z = 0 });
    try std.testing.expect(Viewports.QuadPixelOnRay(quad, past, VIEW, picture, .OnView) == null);
    try std.testing.expectApproxEqAbs(@as(f32, 900), Viewports.QuadPixelOnRay(quad, past, VIEW, picture, .Unbounded).?.x, 0.5);
}

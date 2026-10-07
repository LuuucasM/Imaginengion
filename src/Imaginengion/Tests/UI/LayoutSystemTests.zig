//! The layout pass on real entities: finding the trees that are dirty, laying them out, and writing the results
//! back. No window or renderer needed, so only quads: text needs a loaded font, and how text is measured is
//! covered by TextLayoutTests. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const LayoutSystem = @import("../../UI/LayoutSystem.zig");
const Layout = @import("../../UI/Layout.zig");
const PhysicsManager = @import("../../Physics/PhysicsManager.zig");

const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const LayoutComponent = EntityComponents.LayoutComponent;
const LayoutItemComponent = EntityComponents.LayoutItemComponent;
const LayoutDirtyTag = EntityComponents.LayoutDirtyTag;
const QuadComponent = EntityComponents.QuadComponent;
const TransformComponent = EntityComponents.TransformComponent;
const TransformDirtyTag = EntityComponents.TransformDirtyTag;
const SceneComponent = @import("../../ECSComponents/SComponents.zig").SceneComponent;
const LayoutHiddenTag = EntityComponents.LayoutHiddenTag;

const SEventData = @import("../../Events/SManagerData.zig");
const EEventData = @import("../../Events/EManagerData.zig");
const ECSEventData = @import("../../Events/ECSEventData.zig");

const MathTypes = @import("../../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;
const Vec3 = MathTypes.Vec3;

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

    /// An overlay scene that has already been drawn on a 1920 x 1080 screen at one canvas unit per pixel
    fn DrawnOverlay(self: *TestWorld) !Scene {
        const engine_context = self.mEngineContext;
        const scene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
        scene.GetComponent(SceneComponent).?.mLayoutArea = .{ .x = 1920, .y = 1080 };
        return scene;
    }

    fn Update(self: *TestWorld) !void {
        try LayoutSystem.UpdateLayouts(&self.mEngineContext.mEditorWorld, self.mEngineContext);
    }

    /// EditorProgram.OnUpdate's end of frame for the editor world, where queued removals and deletes happen
    fn EndFrame(self: *TestWorld) !void {
        const engine_context = self.mEngineContext;
        const world = &engine_context.mEditorWorld;
        var callback_list: std.DoublyLinkedList = .{};
        try world.ProcessEvents(SEventData, .EndOfFrame, engine_context, &callback_list);
        try world.ProcessEvents(EEventData, .EndOfFrame, engine_context, &callback_list);
        try world.ProcessEvents(ECSEventData, .EndOfFrame, engine_context, &callback_list);
    }
};

/// An entity in `scene`, under `parent` if there is one
fn New(engine_context: *EngineContext, scene: Scene, parent: ?Entity) !Entity {
    if (parent) |p| return try p.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
    return try scene.CreateEntity(engine_context, Entity.DefaultConfig);
}

/// A layout element with a quad for a background
fn Element(engine_context: *EngineContext, scene: Scene, parent: ?Entity, item: LayoutItemComponent, container: ?LayoutComponent) !Entity {
    const entity = try New(engine_context, scene, parent);
    _ = try entity.AddComponent(engine_context, item);
    if (container) |layout| _ = try entity.AddComponent(engine_context, layout);
    _ = try entity.AddComponent(engine_context, QuadComponent{});
    return entity;
}

fn Fixed(x: f32, y: f32) LayoutItemComponent {
    return .{ .mWidth = .{ .Fixed = x }, .mHeight = .{ .Fixed = y } };
}

fn ExpectXY(expected_x: f32, expected_y: f32, entity: Entity) !void {
    const translation = entity.GetComponent(TransformComponent).?.GetTranslation();
    try std.testing.expectApproxEqAbs(expected_x, translation.x, eps);
    try std.testing.expectApproxEqAbs(expected_y, translation.y, eps);
}

fn ExpectQuad(expected_x: f32, expected_y: f32, entity: Entity) !void {
    const size = entity.GetComponent(QuadComponent).?.mSize;
    try std.testing.expectApproxEqAbs(expected_x, size.x, eps);
    try std.testing.expectApproxEqAbs(expected_y, size.y, eps);
}

/// Pong's menu from the layout tests, as entities, plus a sparkle placed by hand
const PongMenu = struct {
    mMenu: Entity,
    mTitle: Entity,
    mPlay: Entity,
    mPlayLabel: Entity,
    mQuit: Entity,
    mSparkle: Entity,

    fn Build(engine_context: *EngineContext, scene: Scene) !PongMenu {
        const menu = try Element(engine_context, scene, null, .{ .mPlacement = .{ .Anchored = .{} } }, .{
            .mDirection = .Column,
            .mPadding = .All(40),
            .mGap = 20,
            .mCrossAlign = .Center,
        });
        const button_item = LayoutItemComponent{ .mWidth = .{ .Fixed = 300 } };
        const button_layout = LayoutComponent{ .mDirection = .Row, .mPadding = .All(12), .mMainAlign = .Center, .mCrossAlign = .Center };

        const title = try Element(engine_context, scene, menu, Fixed(200, 80), null);
        const play = try Element(engine_context, scene, menu, button_item, button_layout);
        const play_label = try Element(engine_context, scene, play, Fixed(60, 32), null);
        const quit = try Element(engine_context, scene, menu, button_item, button_layout);
        _ = try Element(engine_context, scene, quit, Fixed(60, 32), null);

        //no layout components: layout leaves it alone
        const sparkle = try New(engine_context, scene, menu);
        _ = try sparkle.AddComponent(engine_context, QuadComponent{ .mSize = .{ .x = 7, .y = 7 } });
        try sparkle.SetTranslation(engine_context, .{ .x = 150, .y = 100, .z = 3 });

        return .{ .mMenu = menu, .mTitle = title, .mPlay = play, .mPlayLabel = play_label, .mQuit = quit, .mSparkle = sparkle };
    }
};

test "a dirty tree is laid out: positions, backgrounds and computed sizes, from one tag anywhere in it" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const ui = try PongMenu.Build(engine_context, try world.DrawnOverlay());
    //deep inside the tree, and the whole tree is done
    try ui.mPlayLabel.MarkLayoutDirty(engine_context);
    try world.Update();

    try ExpectXY(0, 0, ui.mMenu);
    try ExpectXY(0, 76, ui.mTitle);
    try ExpectXY(0, -12, ui.mPlay);
    try ExpectXY(0, -88, ui.mQuit);
    try ExpectXY(0, 0, ui.mPlayLabel);

    try ExpectQuad(380, 312, ui.mMenu);
    try ExpectQuad(300, 56, ui.mPlay);
    try ExpectQuad(60, 32, ui.mPlayLabel);
    try std.testing.expectEqual(@as(f32, 380), ui.mMenu.GetComponent(LayoutItemComponent).?.mComputedSize.x);

    //the sparkle has no layout components, so it stays where it was put, at the size it was given
    const sparkle_translation = ui.mSparkle.GetComponent(TransformComponent).?.GetTranslation();
    try std.testing.expectEqual(Vec3(f32){ .x = 150, .y = 100, .z = 3 }, sparkle_translation);
    try ExpectQuad(7, 7, ui.mSparkle);

    try std.testing.expectEqual(@as(usize, 0), engine_context.mEditorWorld.NumEntitiesWith(LayoutDirtyTag));
}

test "layout never moves anything in depth" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const ui = try PongMenu.Build(engine_context, try world.DrawnOverlay());
    try ui.mTitle.SetTranslation(engine_context, .{ .x = 999, .y = 999, .z = 0.5 });
    try ui.mMenu.MarkLayoutDirty(engine_context);
    try world.Update();

    try ExpectXY(0, 76, ui.mTitle);
    try std.testing.expectEqual(@as(f32, 0.5), ui.mTitle.GetComponent(TransformComponent).?.GetTranslation().z);
}

test "laying out a tree that hasn't changed doesn't dirty any transforms" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const ui = try PongMenu.Build(engine_context, try world.DrawnOverlay());
    try ui.mMenu.MarkLayoutDirty(engine_context);
    try world.Update();
    try PhysicsManager.UpdateWorldTransforms(&engine_context.mEditorWorld, engine_context);
    try std.testing.expectEqual(@as(usize, 0), engine_context.mEditorWorld.NumEntitiesWith(TransformDirtyTag));

    try ui.mQuit.MarkLayoutDirty(engine_context);
    try world.Update();
    try std.testing.expectEqual(@as(usize, 0), engine_context.mEditorWorld.NumEntitiesWith(TransformDirtyTag));
}

test "an overlay tree waits until its scene has been drawn" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    //pinned to the top right corner of the screen
    const corner = try Element(engine_context, scene, null, .{
        .mWidth = .{ .Fixed = 100 },
        .mHeight = .{ .Fixed = 50 },
        .mPlacement = .{ .Anchored = .{ .Anchor = .{ .x = 1, .y = 1 }, .Pivot = .{ .x = 1, .y = 1 } } },
    }, null);
    try corner.MarkLayoutDirty(engine_context);

    //no screen to fit into yet: nothing moves, and it stays dirty
    try world.Update();
    try ExpectXY(0, 0, corner);
    try std.testing.expect(corner.HasComponent(LayoutDirtyTag));

    scene.GetComponent(SceneComponent).?.mLayoutArea = .{ .x = 1000, .y = 600 };
    try world.Update();
    try ExpectXY(450, 275, corner);
    try std.testing.expect(!corner.HasComponent(LayoutDirtyTag));
}

test "a panel in the world is sized by layout but stays where it was put" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const panel = try Element(engine_context, scene, null, Fixed(400, 300), .{ .mPadding = .All(10) });
    try panel.SetTranslation(engine_context, .{ .x = 5, .y = 6, .z = 7 });
    const child = try Element(engine_context, scene, panel, Fixed(50, 20), null);
    try panel.MarkLayoutDirty(engine_context);
    try world.Update();

    try std.testing.expectEqual(Vec3(f32){ .x = 5, .y = 6, .z = 7 }, panel.GetComponent(TransformComponent).?.GetTranslation());
    try ExpectQuad(400, 300, panel);
    //at the top left of the inside, relative to the panel
    try ExpectXY(-165, 130, child);
}

test "a container without an item fits its children, and one under a hand-placed entity is a tree of its own" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try world.DrawnOverlay();

    //a column with no LayoutItemComponent, and a hand-placed entity in it
    const column = try New(engine_context, scene, null);
    _ = try column.AddComponent(engine_context, LayoutComponent{ .mGap = 10 });
    _ = try column.AddComponent(engine_context, QuadComponent{});
    _ = try Element(engine_context, scene, column, Fixed(40, 20), null);
    const holder = try New(engine_context, scene, column);
    try holder.SetTranslation(engine_context, .{ .x = 500, .y = 500, .z = 0 });
    //a row under the hand-placed holder: it isn't in the column's tree, it's the root of its own
    const row = try Element(engine_context, scene, holder, .{}, .{ .mDirection = .Row, .mGap = 5 });
    const a = try Element(engine_context, scene, row, Fixed(10, 10), null);
    const b = try Element(engine_context, scene, row, Fixed(10, 10), null);

    //adding the components tagged both trees
    try world.Update();
    //the holder takes no room in the column, which fits the one child it lays out
    try ExpectQuad(40, 20, column);
    try ExpectXY(500, 500, holder);
    try ExpectQuad(25, 10, row);
    try ExpectXY(-7.5, 0, a);
    try ExpectXY(7.5, 0, b);

    //a change in the row's tree lays out only the row's tree: the column's background, scribbled on, stays scribbled
    column.GetComponent(QuadComponent).?.mSize = .{ .x = 1, .y = 1 };
    row.GetComponent(LayoutComponent).?.mGap = 15;
    try b.MarkLayoutDirty(engine_context);
    try world.Update();
    try ExpectQuad(35, 10, row);
    try ExpectQuad(1, 1, column);
}

test "an entity that is no longer in any layout just loses its tag" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try world.DrawnOverlay();

    const plain = try New(engine_context, scene, null);
    try plain.SetTranslation(engine_context, .{ .x = 3, .y = 4, .z = 0 });
    try plain.MarkLayoutDirty(engine_context);
    try world.Update();

    try std.testing.expect(!plain.HasComponent(LayoutDirtyTag));
    try ExpectXY(3, 4, plain);
}

//---------------------------the screen an overlay fits---------------------------

const CameraView = @import("../../Renderer/Renderer.zig").CameraView;

/// A view drawing into a width x height target
fn ViewOf(width: f32, height: f32, display_scale: f32) CameraView {
    return .{
        .Pose = .{ .Position = .{ .x = 0, .y = 0, .z = 0 }, .Rotation = .{ .w = 1, .x = 0, .y = 0, .z = 0 } },
        .TanHalfFov = 0.57735,
        .TargetWidth = width,
        .TargetHeight = height,
        .FarDistance = 1000,
        .DisplayScale = display_scale,
    };
}

test "drawing an overlay records its screen, and only a changed screen lays it out again" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const game_world = &engine_context.mEditorWorld;

    game_world.mOverlayScaleMode = .ScaleWithScreen;
    const scene = try game_world.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    //pinned to the top right corner, with a child that doesn't need its own tag
    const corner = try Element(engine_context, scene, null, .{
        .mWidth = .{ .Fixed = 100 },
        .mHeight = .{ .Fixed = 50 },
        .mPlacement = .{ .Anchored = .{ .Anchor = .{ .x = 1, .y = 1 }, .Pivot = .{ .x = 1, .y = 1 } } },
    }, .{});
    const inside = try Element(engine_context, scene, corner, Fixed(10, 10), null);
    const scenes = [_]Scene.Type{scene.mID};
    //adding their components asked for a layout; start from nothing asked for, to see what drawing asks for
    try corner.ClearLayoutDirty(engine_context);
    try inside.ClearLayoutDirty(engine_context);

    //scale with screen is 1080 units tall whatever the height, so a 1080p view is one unit per pixel
    try LayoutSystem.RecordViewArea(game_world, &scenes, ViewOf(1920, 1080, 1), engine_context);
    try std.testing.expect(corner.HasComponent(LayoutDirtyTag));
    try std.testing.expect(!inside.HasComponent(LayoutDirtyTag));
    try world.Update();
    try ExpectXY(910, 515, corner);

    //the same shape at 720p is the same canvas, so nothing to redo
    try LayoutSystem.RecordViewArea(game_world, &scenes, ViewOf(1280, 720, 1), engine_context);
    try std.testing.expect(!corner.HasComponent(LayoutDirtyTag));

    //narrower is a different canvas: the corner follows the new right edge
    try LayoutSystem.RecordViewArea(game_world, &scenes, ViewOf(1000, 1080, 1), engine_context);
    try std.testing.expect(corner.HasComponent(LayoutDirtyTag));
    try world.Update();
    try ExpectXY(450, 515, corner);
}

test "a constant pixel size world's overlays fit its size in pixels over the display scale, every one the same" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    engine_context.mEditorWorld.mOverlayScaleMode = .ConstantPixelSize;
    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    const other = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    const scenes = [_]Scene.Type{ scene.mID, other.mID };

    try LayoutSystem.RecordViewArea(&engine_context.mEditorWorld, &scenes, ViewOf(1600, 900, 2), engine_context);
    for ([_]Scene{ scene, other }) |overlay| {
        const area = overlay.GetComponent(SceneComponent).?.mLayoutArea.?;
        try std.testing.expectApproxEqAbs(@as(f32, 800), area.x, eps);
        try std.testing.expectApproxEqAbs(@as(f32, 450), area.y, eps);
    }
}

test "a game scene among the overlays records nothing" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const level = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const scenes = [_]Scene.Type{level.mID};

    try LayoutSystem.RecordViewArea(&engine_context.mEditorWorld, &scenes, ViewOf(1600, 900, 1), engine_context);
    try std.testing.expect(level.GetComponent(SceneComponent).?.mLayoutArea == null);
}

//------------------------------what asks for a layout------------------------------

/// A column of three 10 tall children with gaps of 10, laid out once so nothing is left asking
const Stack = struct {
    mColumn: Entity,
    mA: Entity,
    mB: Entity,
    mC: Entity,

    fn Build(world: *TestWorld, scene: Scene) !Stack {
        const engine_context = world.mEngineContext;
        const column = try Element(engine_context, scene, null, .{ .mPlacement = .{ .Anchored = .{} } }, .{ .mGap = 10 });
        const stack = Stack{
            .mColumn = column,
            .mA = try Element(engine_context, scene, column, Fixed(10, 10), null),
            .mB = try Element(engine_context, scene, column, Fixed(10, 10), null),
            .mC = try Element(engine_context, scene, column, Fixed(10, 10), null),
        };
        try world.Update();
        try std.testing.expectEqual(@as(usize, 0), engine_context.mEditorWorld.NumEntitiesWith(LayoutDirtyTag));
        return stack;
    }
};

test "adding an element to a container lays its tree out" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try world.DrawnOverlay();
    const stack = try Stack.Build(world, scene);

    //no tag by hand: adding the component is what asks
    _ = try Element(engine_context, scene, stack.mColumn, Fixed(10, 10), null);
    try world.Update();

    try ExpectQuad(10, 70, stack.mColumn);
    try ExpectXY(0, 30, stack.mA);
}

test "a duplicate in a layout asks for its tree to be laid out" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const stack = try Stack.Build(world, try world.DrawnOverlay());

    const copy = try stack.mB.Duplicate(engine_context);
    try std.testing.expect(copy.HasComponent(LayoutDirtyTag));
}

test "removing an element's item closes its gap, even when asked for before the layout pass" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const stack = try Stack.Build(world, try world.DrawnOverlay());

    try stack.mB.RemoveComponent(engine_context, LayoutItemComponent);
    //the pass in the same frame still sees the item: the removal is only queued until the end of the frame
    try world.Update();
    try ExpectQuad(10, 50, stack.mColumn);

    //it happens, and asks for the column to be laid out without it
    try world.EndFrame();
    try std.testing.expect(stack.mColumn.HasComponent(LayoutDirtyTag));
    try world.Update();
    try ExpectQuad(10, 30, stack.mColumn);
    try ExpectXY(0, -10, stack.mC);
}

test "deleting an element closes its gap" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const stack = try Stack.Build(world, try world.DrawnOverlay());

    try stack.mA.Delete(engine_context);
    try world.EndFrame();
    try world.Update();

    try ExpectQuad(10, 30, stack.mColumn);
    try ExpectXY(0, 10, stack.mB);
    try ExpectXY(0, -10, stack.mC);
}

test "a container that stops being one leaves its children as trees of their own" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const stack = try Stack.Build(world, try world.DrawnOverlay());

    try stack.mColumn.RemoveComponent(engine_context, LayoutComponent);
    try world.EndFrame();
    for ([_]Entity{ stack.mA, stack.mB, stack.mC }) |child| {
        try std.testing.expect(child.HasComponent(LayoutDirtyTag));
    }

    //each a root now: sized, and left where it was
    try world.Update();
    try ExpectXY(0, 20, stack.mA);
    try std.testing.expectEqual(@as(usize, 0), engine_context.mEditorWorld.NumEntitiesWith(LayoutDirtyTag));
}

test "a translation set by hand on something layout places is put back, keeping its depth" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const stack = try Stack.Build(world, try world.DrawnOverlay());

    try stack.mB.SetTranslation(engine_context, .{ .x = 300, .y = 300, .z = 0.7 });
    try std.testing.expect(stack.mB.HasComponent(LayoutDirtyTag));
    try world.Update();

    try ExpectXY(0, 0, stack.mB);
    try std.testing.expectEqual(@as(f32, 0.7), stack.mB.GetComponent(TransformComponent).?.GetTranslation().z);
    //and putting it back isn't taken for another hand-set translation
    try std.testing.expectEqual(@as(usize, 0), engine_context.mEditorWorld.NumEntitiesWith(LayoutDirtyTag));
}

test "a translation set by hand on something layout doesn't place stays" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try world.DrawnOverlay();

    //placed by hand, and a root nothing anchors
    const plain = try New(engine_context, scene, null);
    const free_root = try Element(engine_context, scene, null, Fixed(10, 10), .{});
    try world.Update();

    try plain.SetTranslation(engine_context, .{ .x = 1, .y = 2, .z = 3 });
    try free_root.SetTranslation(engine_context, .{ .x = 4, .y = 5, .z = 6 });
    try std.testing.expect(!plain.HasComponent(LayoutDirtyTag));
    try std.testing.expect(!free_root.HasComponent(LayoutDirtyTag));
}

test "a collapsed element and everything under it are hidden, and shown again when expanded" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try world.DrawnOverlay();

    const column = try Element(engine_context, scene, null, .{}, .{});
    const shown = try Element(engine_context, scene, column, Fixed(10, 10), null);
    //a tree node: a header, and its contents folded away under it
    const node = try Element(engine_context, scene, column, .{ .mCollapsed = true }, .{});
    const by_hand = try New(engine_context, scene, node);
    const inner = try Element(engine_context, scene, node, .{ .mCollapsed = true }, .{});
    const inner_child = try Element(engine_context, scene, inner, Fixed(10, 10), null);
    try world.Update();

    try std.testing.expect(!shown.HasComponent(LayoutHiddenTag));
    for ([_]Entity{ node, by_hand, inner, inner_child }) |entity| {
        try std.testing.expect(entity.HasComponent(LayoutHiddenTag));
    }

    //expanding the outer one shows it, but the inner one is still collapsed itself
    node.GetComponent(LayoutItemComponent).?.mCollapsed = false;
    try node.MarkLayoutDirty(engine_context);
    try world.Update();
    try std.testing.expect(!node.HasComponent(LayoutHiddenTag));
    try std.testing.expect(!by_hand.HasComponent(LayoutHiddenTag));
    try std.testing.expect(inner.HasComponent(LayoutHiddenTag));
    try std.testing.expect(inner_child.HasComponent(LayoutHiddenTag));
}

//------------------------------adding layout in the editor------------------------------

const ComponentList = @import("../../EditorPanels/ComponentList.zig");

test "adding layout from the panel keeps a quad the size it is" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try world.DrawnOverlay();

    //an item on a quad starts fixed at the quad's size, where fitting would shrink it to nothing
    const panel = try New(engine_context, scene, null);
    _ = try panel.AddComponent(engine_context, QuadComponent{ .mSize = .{ .x = 30, .y = 20 } });
    try ComponentList.AddFromPanel(LayoutItemComponent, engine_context, panel);
    try world.Update();
    try ExpectQuad(30, 20, panel);

    //a container on a quad comes with an item like that
    const box = try New(engine_context, scene, null);
    _ = try box.AddComponent(engine_context, QuadComponent{ .mSize = .{ .x = 8, .y = 6 } });
    try ComponentList.AddFromPanel(LayoutComponent, engine_context, box);
    try std.testing.expect(box.HasComponent(LayoutItemComponent));
    try world.Update();
    try ExpectQuad(8, 6, box);

    //with no quad there's nothing to keep, so the defaults it has always had
    const bare = try New(engine_context, scene, null);
    try ComponentList.AddFromPanel(LayoutComponent, engine_context, bare);
    try std.testing.expect(!bare.HasComponent(LayoutItemComponent));
    try ComponentList.AddFromPanel(LayoutItemComponent, engine_context, bare);
    try std.testing.expectEqual(Layout.Sizing.Fit, bare.GetComponent(LayoutItemComponent).?.mWidth);
}

test "a child laid out in a panel in the world is gathered for drawing where layout put it" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const ShapeGeometry = @import("../../Renderer/ShapeGeometry.zig");

    const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const panel = try New(engine_context, scene, null);
    _ = try panel.AddComponent(engine_context, LayoutComponent{});
    _ = try panel.AddComponent(engine_context, Fixed(200, 200));
    const child = try New(engine_context, scene, panel);
    _ = try child.AddComponent(engine_context, LayoutItemComponent{ .mWidth = .{ .Fill = 1 }, .mHeight = .{ .Fill = 1 } });
    _ = try child.AddComponent(engine_context, QuadComponent{});

    try world.Update();
    try PhysicsManager.UpdateWorldTransforms(&engine_context.mEditorWorld, engine_context);

    //the panel has no quad, so the child is all there is to draw: filling the panel, at its middle
    const shapes = try ShapeGeometry.GatherViewShapes(engine_context.FrameAllocator(), &engine_context.mEditorWorld, ViewOf(1600, 900, 1), .{ .Overlays = &.{} }, ShapeGeometry.VISUALS_QUERY);
    try std.testing.expectEqual(@as(usize, 1), shapes.items.len);
    try std.testing.expectEqual(child.mID, shapes.items[0].Entity.mID);
    const box = ShapeGeometry.QuadBox(child.GetComponent(TransformComponent).?, child.GetComponent(QuadComponent).?, null);
    try std.testing.expectEqual(Vec3(f32){ .x = 0, .y = 0, .z = 0 }, box.Center);
    try std.testing.expectApproxEqAbs(@as(f32, 100), box.HalfExtents.x, eps);
    try std.testing.expectApproxEqAbs(@as(f32, 100), box.HalfExtents.y, eps);
}

test "a grid of entities: the content browser's icons wrapping in a panel" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const scene = try world.DrawnOverlay();

    //a 200 wide panel, with 60 x 70 icons 10 apart: three fit across
    const panel = try Element(engine_context, scene, null, .{ .mWidth = .{ .Fixed = 200 } }, .{ .mDirection = .Grid, .mGap = 10 });
    var icons: [4]Entity = undefined;
    for (&icons) |*icon| icon.* = try Element(engine_context, scene, panel, Fixed(60, 70), null);

    try world.Update();
    try ExpectQuad(200, 150, panel);
    try ExpectXY(-70, 40, icons[0]);
    try ExpectXY(70, 40, icons[2]);
    try ExpectXY(-70, -40, icons[3]);

    //a set count of two
    panel.GetComponent(LayoutComponent).?.mColumns = .{ .Count = 2 };
    try panel.MarkLayoutDirty(engine_context);
    try world.Update();
    try ExpectXY(-70, -40, icons[2]);
}

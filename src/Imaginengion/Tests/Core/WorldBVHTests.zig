//! WorldBVH: a world's two trees, built over every scene once a frame and refit as things move. No window or renderer
//! needed, texts are laid out in a stand in font. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const WorldBVH = @import("../../Core/WorldBVH.zig");
const BVH = @import("../../Core/BVH.zig");
const Aabb = @import("../../Math/Aabb.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const ShapeGeometry = @import("../../Renderer/ShapeGeometry.zig");
const CameraView = @import("../../Renderer/Renderer.zig").CameraView;
const PhysicsManager = @import("../../Physics/PhysicsManager.zig");
const MathTypes = @import("../../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;
const Vec3 = MathTypes.Vec3;

const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const ShapeComponent = EntityComponents.ShapeComponent;
const SurfaceComponent = EntityComponents.SurfaceComponent;
const TextComponent = EntityComponents.TextComponent;
const ColliderComponent = EntityComponents.ColliderComponent;
const RigidBodyComponent = EntityComponents.RigidBodyComponent;
const MergeComponent = EntityComponents.MergeComponent;
const LayoutHiddenTag = EntityComponents.LayoutHiddenTag;
const TransformComponent = EntityComponents.TransformComponent;

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

    /// WorldManager.BuildBVH, with texts in the stand in font
    fn Build(self: *TestWorld) !*WorldBVH {
        const engine_context = self.mEngineContext;
        const world = &engine_context.mEditorWorld;
        try PhysicsManager.UpdateWorldTransforms(world, engine_context);
        try world.mBVH.BuildWith(engine_context, world, TestFonts{});
        return &world.mBVH;
    }
};

//---------------------------a stand in font: every letter the same half unit wide box---------------------------

const TestGlyph = struct {
    mAtlasTexel0: Vec2(f32) = .{ .x = 0, .y = 10 },
    mAtlasTexel1: Vec2(f32) = .{ .x = 10, .y = 0 },
    mPlaneMin: Vec2(f32), //left, top
    mPlaneMax: Vec2(f32), //right, bottom
    mAdvance: f32,
    mKernings: std.AutoHashMapUnmanaged(u16, f32) = .empty,
};

const LETTER_IND = 0;
const SPACE_IND = 1;

const TestFont = struct {
    mGlyphs: [2]TestGlyph = .{
        .{ .mPlaneMin = .{ .x = 0, .y = 0.7 }, .mPlaneMax = .{ .x = 0.5, .y = 0 }, .mAdvance = 0.6 },
        //no plane bounds: nothing to draw
        .{ .mPlaneMin = .{ .x = 0, .y = 0 }, .mPlaneMax = .{ .x = 0, .y = 0 }, .mAdvance = 0.3 },
    },
    mLineHeight: f32 = 1.2,
    mAscender: f32 = 0.9,
    mDescender: f32 = -0.2,
    mAtlasSize: Vec2(f32) = .{ .x = 100, .y = 100 },

    pub fn ToArrayIndex(unicode: usize) usize {
        return if (unicode == ' ') SPACE_IND else LETTER_IND;
    }
};

const TEST_FONT = TestFont{};

const TestFonts = struct {
    pub fn Get(_: TestFonts, _: *const TextComponent) !*const TestFont {
        return &TEST_FONT;
    }
};

//------------------------------------------------helpers------------------------------------------------

fn AddQuad(engine_context: *EngineContext, scene: Scene, position: Vec3(f32)) !Entity {
    const entity = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    try entity.SetTranslation(engine_context, position);
    _ = try entity.AddComponent(engine_context, ShapeComponent{});
    _ = try entity.AddComponent(engine_context, SurfaceComponent{});
    return entity;
}

fn AddText(engine_context: *EngineContext, scene: Scene, text: []const u8, position: Vec3(f32)) !Entity {
    const entity = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
    try entity.SetTranslation(engine_context, position);
    const text_component = try entity.AddComponent(engine_context, TextComponent{});
    try text_component.SetText(engine_context, text);
    _ = try entity.AddComponent(engine_context, SurfaceComponent{});
    return entity;
}

/// The items of `tree` that stand for `entity`
fn ItemsOf(tree: *const WorldBVH.LayerTree, entity: Entity) usize {
    var count: usize = 0;
    for (tree.mItems.items) |item| {
        if (item.Entity == entity.mID) count += 1;
    }
    return count;
}

/// Where `entity`'s one item is in `tree`
fn IndexOf(tree: *const WorldBVH.LayerTree, entity: Entity) usize {
    for (tree.mItems.items, 0..) |item, i| {
        if (item.Entity == entity.mID) return i;
    }
    unreachable;
}

fn BoxHolds(outer: Aabb, inner: Aabb) bool {
    return outer.Contains(inner.Min) and outer.Contains(inner.Max);
}

/// Every item is inside its leaf's box, and every node inside its parent's, so a walk that skips a box skips nothing
/// in it
fn ExpectTreeHoldsItems(tree: *const WorldBVH.LayerTree) !void {
    const nodes = tree.mNodes.items;
    try std.testing.expectEqual(tree.mItems.items.len, tree.mBVHItems.items.len);
    for (nodes, 0..) |node, node_ind| {
        if (node.IsLeaf()) {
            for (tree.mBVHItems.items[node.FirstItem()..][0..node.ItemCount()]) |item| {
                try std.testing.expect(BoxHolds(node.Bounds(), item.Bounds));
                try std.testing.expect(node.ItemMask() & item.Mask == item.Mask);
            }
        } else {
            try std.testing.expect(BoxHolds(node.Bounds(), nodes[node_ind + 1].Bounds()));
            try std.testing.expect(BoxHolds(node.Bounds(), nodes[node.RightChild()].Bounds()));
        }
    }
}

fn ExpectNear(expected: Vec3(f32), actual: Vec3(f32)) !void {
    try std.testing.expectApproxEqAbs(expected.x, actual.x, 0.0001);
    try std.testing.expectApproxEqAbs(expected.y, actual.y, 0.0001);
    try std.testing.expectApproxEqAbs(expected.z, actual.z, 0.0001);
}

//-------------------------------------------------tests-------------------------------------------------

test "quads, letters, merges and colliders each get items in their own layer, with their scene and their systems" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const editor_world = &engine_context.mEditorWorld;

    const level = try editor_world.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const hud = try editor_world.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);

    const rock = try AddQuad(engine_context, level, .{ .x = 0, .y = 0, .z = 0 });
    const wall = try level.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try wall.AddComponent(engine_context, ColliderComponent{});
    //a merge of two quads is one item, its root's
    const merge = try level.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try merge.AddComponent(engine_context, MergeComponent{});
    for ([_]f32{ 5, 6 }) |x| {
        const part = try merge.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
        try part.SetTranslation(engine_context, .{ .x = x, .y = 0, .z = 0 });
        _ = try part.AddComponent(engine_context, ShapeComponent{});
        _ = try part.AddComponent(engine_context, SurfaceComponent{});
    }

    //two letters and a space, and a see-through quad that draws nothing but still takes clicks
    const label = try AddText(engine_context, hud, "A A", .{ .x = 0, .y = 0, .z = 0 });
    const row_button = try AddQuad(engine_context, hud, .{ .x = 0, .y = -50, .z = 0 });
    const row_surface = row_button.GetComponentMut(SurfaceComponent).?;
    row_surface.mTexOptions.mIsTransparent = true;
    row_surface.mTexOptions.mColor.w = 0;
    row_surface.mBorderWidth = 0;

    const bvh = try world.Build();
    const game = &bvh.mGame;
    const overlay = &bvh.mOverlay;

    try std.testing.expectEqual(@as(usize, 3), game.mItems.items.len);
    try std.testing.expectEqual(@as(usize, 1), ItemsOf(game, rock));
    try std.testing.expectEqual(@as(usize, 1), ItemsOf(game, wall));
    try std.testing.expectEqual(@as(usize, 1), ItemsOf(game, merge));
    //two letters and the whole text
    try std.testing.expectEqual(@as(usize, 4), overlay.mItems.items.len);
    try std.testing.expectEqual(@as(usize, 3), ItemsOf(overlay, label));
    try std.testing.expectEqual(@as(usize, 1), ItemsOf(overlay, row_button));

    const Expected = struct { Tree: *const WorldBVH.LayerTree, Entity: Entity, Kind: WorldBVH.ItemKind, Mask: u4 };
    const expected = [_]Expected{
        .{ .Tree = game, .Entity = rock, .Kind = .Quad, .Mask = BVH.Mask.RENDER | BVH.Mask.PICK },
        .{ .Tree = game, .Entity = wall, .Kind = .Collider, .Mask = BVH.Mask.PHYSICS },
        .{ .Tree = game, .Entity = merge, .Kind = .Merge, .Mask = BVH.Mask.RENDER | BVH.Mask.PICK },
        .{ .Tree = overlay, .Entity = row_button, .Kind = .Quad, .Mask = BVH.Mask.PICK },
    };
    for (expected) |want| {
        const ind = IndexOf(want.Tree, want.Entity);
        try std.testing.expectEqual(want.Kind, want.Tree.mItems.items[ind].Kind);
        try std.testing.expectEqual(want.Mask, want.Tree.mBVHItems.items[ind].Mask);
    }
    //the letters are drawn, the whole text is what is clicked
    var letters: usize = 0;
    for (overlay.mItems.items, overlay.mBVHItems.items) |item, bvh_item| {
        if (item.Entity != label.mID) continue;
        switch (item.Kind) {
            .Glyph => {
                letters += 1;
                try std.testing.expectEqual(BVH.Mask.RENDER, bvh_item.Mask);
            },
            .Text => try std.testing.expectEqual(BVH.Mask.PICK, bvh_item.Mask),
            else => return error.TestUnexpectedResult,
        }
    }
    try std.testing.expectEqual(@as(usize, 2), letters);

    //each item knows its scene, and a view showing only the HUD names only its slot
    for (game.mItems.items) |item| try std.testing.expectEqual(level.mID, bvh.mScenes.items[item.SceneSlot]);
    for (overlay.mItems.items) |item| try std.testing.expectEqual(hud.mID, bvh.mScenes.items[item.SceneSlot]);
    const hud_slot = overlay.mItems.items[0].SceneSlot;
    try std.testing.expectEqual(@as(u64, 1) << @intCast(hud_slot), bvh.SceneBits(&.{hud.mID}));
    try std.testing.expectEqual(@as(u64, 0b11), bvh.SceneBits(&.{ hud.mID, level.mID }));

    try ExpectTreeHoldsItems(game);
    try ExpectTreeHoldsItems(overlay);
}

test "each letter's item is placed from its own layout, after the build has reordered them" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const level = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    //enough letters over two lines that the build has to sort them
    const text = try AddText(engine_context, level, "AAAAAA\nAAAAAA", .{ .x = 3, .y = 2, .z = 0 });
    try text.SetScale(engine_context, .{ .x = 2, .y = 1, .z = 1 });

    const bvh = try world.Build();
    const tree = &bvh.mGame;
    //twelve letters and the whole text
    try std.testing.expectEqual(@as(usize, 13), tree.mItems.items.len);

    const transform = text.GetComponent(TransformComponent).?;
    const params = ShapeGeometry.GetTextParams(transform, text.GetComponent(TextComponent).?);
    var placements_seen: [12]bool = @splat(false);
    for (tree.mItems.items, tree.mBVHItems.items) |item, bvh_item| {
        if (item.Kind != .Glyph) continue;
        try std.testing.expect(!placements_seen[item.Index]);
        placements_seen[item.Index] = true;
        const box = ShapeGeometry.GlyphBox(transform, params, bvh.mGlyphs.items[item.Index], null);
        try ExpectNear(box.Center, bvh_item.Bounds.Center());
    }
    try ExpectTreeHoldsItems(tree);
}

test "a letter's box in canvas units, placed by a view's canvas, is the box that view draws it with" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const hud = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    const text = try AddText(engine_context, hud, "AA", .{ .x = 120, .y = -40, .z = 0 });
    try text.SetScale(engine_context, .{ .x = 3, .y = 2, .z = 1 });
    try PhysicsManager.UpdateWorldTransforms(&engine_context.mEditorWorld, engine_context);

    const view = CameraView{
        .Pose = .{ .Position = .{ .x = 4, .y = 1, .z = 7 }, .Rotation = .{ .w = 0.9238795, .x = 0, .y = 0.3826834, .z = 0 } },
        .TanHalfFov = 0.57735,
        .TargetWidth = 1600,
        .TargetHeight = 900,
        .FarDistance = 1000,
        .DisplayScale = 1,
    };
    const canvas = ShapeGeometry.WorldCanvas(&engine_context.mEditorWorld, view);
    const transform = text.GetComponent(TransformComponent).?;
    const params = ShapeGeometry.GetTextParams(transform, text.GetComponent(TextComponent).?);

    var layout = @import("../../Renderer/TextLayout.zig").Iterator(TestFont).Init("AA", &TEST_FONT, params.FontSize, params.WrapWidth);
    while (layout.Next()) |glyph| {
        const in_canvas = ShapeGeometry.GlyphBox(transform, params, glyph, null);
        const drawn = ShapeGeometry.GlyphBox(transform, params, glyph, canvas);
        try ExpectNear(drawn.Center, canvas.ToWorldPoint(in_canvas.Center));
        try std.testing.expectApproxEqAbs(drawn.HalfExtents.x, in_canvas.HalfExtents.x * canvas.Scale, 0.0001);
        try std.testing.expectApproxEqAbs(drawn.HalfExtents.y, in_canvas.HalfExtents.y * canvas.Scale, 0.0001);
    }
}

test "what isn't drawn is left out, but a collider is in whether its entity is shown or not" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const level = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    const shown = try AddQuad(engine_context, level, .{ .x = 0, .y = 0, .z = 0 });
    const folded = try AddQuad(engine_context, level, .{ .x = 1, .y = 0, .z = 0 });
    _ = try folded.AddComponent(engine_context, LayoutHiddenTag{});
    const switched_off = try AddQuad(engine_context, level, .{ .x = 2, .y = 0, .z = 0 });
    switched_off.GetComponentMut(SurfaceComponent).?.mShouldRender = false;
    //physics collides with it either way
    _ = try folded.AddComponent(engine_context, ColliderComponent{});

    const bvh = try world.Build();
    const tree = &bvh.mGame;
    try std.testing.expectEqual(@as(usize, 1), ItemsOf(tree, shown));
    try std.testing.expectEqual(@as(usize, 0), ItemsOf(tree, switched_off));
    try std.testing.expectEqual(@as(usize, 1), ItemsOf(tree, folded));
    try std.testing.expectEqual(WorldBVH.ItemKind.Collider, tree.mItems.items[IndexOf(tree, folded)].Kind);
}

test "a refit follows what has moved, and every box above it still holds it" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const editor_world = &engine_context.mEditorWorld;
    const level = try editor_world.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    //a row of quads, enough for a few levels, and a collider and a text among them
    var quads: [12]Entity = undefined;
    for (&quads, 0..) |*quad, i| quad.* = try AddQuad(engine_context, level, .{ .x = @floatFromInt(i * 2), .y = 0, .z = 0 });
    const ball = try level.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try ball.AddComponent(engine_context, ColliderComponent{});
    const sign = try AddText(engine_context, level, "AA", .{ .x = 0, .y = 4, .z = 0 });

    const bvh = try world.Build();
    const tree = &bvh.mGame;
    const node_count = tree.mNodes.items.len;

    //far off, past every other box, so the root has to grow to hold them
    const moved = quads[3];
    try moved.SetTranslation(engine_context, .{ .x = 100, .y = -30, .z = 5 });
    try ball.SetTranslation(engine_context, .{ .x = -40, .y = 0, .z = 0 });
    try sign.SetTranslation(engine_context, .{ .x = 0, .y = 60, .z = 0 });
    try PhysicsManager.UpdateWorldTransforms(editor_world, engine_context);
    bvh.Refit(engine_context, editor_world, WorldBVH.ALL_ITEMS);

    //the same tree, its boxes moved
    try std.testing.expectEqual(node_count, tree.mNodes.items.len);
    try ExpectNear(.{ .x = 100, .y = -30, .z = 5 }, tree.mBVHItems.items[IndexOf(tree, moved)].Bounds.Center());
    try ExpectNear(.{ .x = -40, .y = 0, .z = 0 }, tree.mBVHItems.items[IndexOf(tree, ball)].Bounds.Center());
    for (tree.mItems.items, tree.mBVHItems.items) |item, bvh_item| {
        if (item.Entity == sign.mID) try std.testing.expect(bvh_item.Bounds.Min.y > 55);
    }
    try ExpectTreeHoldsItems(tree);
}

test "a physics refit places only colliders again, and the tree still holds everything" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const editor_world = &engine_context.mEditorWorld;
    const level = try editor_world.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    const rock = try AddQuad(engine_context, level, .{ .x = 0, .y = 0, .z = 0 });
    const sign = try AddText(engine_context, level, "AA", .{ .x = 0, .y = 4, .z = 0 });
    const ball = try level.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try ball.AddComponent(engine_context, ColliderComponent{});

    const bvh = try world.Build();
    const tree = &bvh.mGame;
    const rock_before = tree.mBVHItems.items[IndexOf(tree, rock)].Bounds;
    //its two letters and the whole text
    var sign_before: [3]Aabb = undefined;
    var sign_count: usize = 0;
    for (tree.mItems.items, tree.mBVHItems.items) |item, bvh_item| {
        if (item.Entity != sign.mID) continue;
        sign_before[sign_count] = bvh_item.Bounds;
        sign_count += 1;
    }

    //everything moves, only the collider is placed again
    for ([_]Entity{ rock, sign, ball }) |entity| try entity.SetTranslation(engine_context, .{ .x = 50, .y = 50, .z = 0 });
    try PhysicsManager.UpdateWorldTransforms(editor_world, engine_context);
    bvh.Refit(engine_context, editor_world, BVH.Mask.PHYSICS);

    try ExpectNear(.{ .x = 50, .y = 50, .z = 0 }, tree.mBVHItems.items[IndexOf(tree, ball)].Bounds.Center());
    try ExpectNear(rock_before.Center(), tree.mBVHItems.items[IndexOf(tree, rock)].Bounds.Center());
    sign_count = 0;
    for (tree.mItems.items, tree.mBVHItems.items) |item, bvh_item| {
        if (item.Entity != sign.mID) continue;
        try ExpectNear(sign_before[sign_count].Center(), bvh_item.Bounds.Center());
        sign_count += 1;
    }
    try ExpectTreeHoldsItems(tree);

    //and the full refit before rendering places the rest
    bvh.Refit(engine_context, editor_world, WorldBVH.ALL_ITEMS);
    try ExpectNear(.{ .x = 50, .y = 50, .z = 0 }, tree.mBVHItems.items[IndexOf(tree, rock)].Bounds.Center());
    try ExpectTreeHoldsItems(tree);
}

test "a physics step keeps a moving body's collider in the tree where its last substep started" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const editor_world = &engine_context.mEditorWorld;
    const level = try editor_world.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    //a dynamic ball falling at a steady speed, no gravity, and a quad that stays put
    const ball = try level.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try ball.AddComponent(engine_context, ColliderComponent{});
    _ = try ball.AddComponent(engine_context, RigidBodyComponent{});
    ball.GetComponentMut(RigidBodyComponent).?.SetVelocity(.{ .x = 0, .y = -6, .z = 0 });
    _ = try AddQuad(engine_context, level, .{ .x = 0, .y = 0, .z = 0 });

    const bvh = try world.Build();
    const tree = &bvh.mGame;
    try editor_world.OnPhysicsUpdate(engine_context);
    //the last substep's move, which the tree hasn't seen
    try PhysicsManager.UpdateWorldTransforms(editor_world, engine_context);

    //refit at the start of every substep, before the bodies move: one substep behind where the ball ended up
    const ball_y = ball.GetComponent(TransformComponent).?.GetWorldPosition().y;
    try std.testing.expect(ball_y < 0);
    const tree_y = tree.mBVHItems.items[IndexOf(tree, ball)].Bounds.Center().y;
    try std.testing.expect(tree_y < 0);
    try std.testing.expect(tree_y > ball_y);
    try ExpectTreeHoldsItems(tree);
}

test "a world with items in more scenes than a view can name is an error" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    for (0..WorldBVH.MAX_SCENES) |_| {
        const scene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
        _ = try AddQuad(engine_context, scene, .{ .x = 0, .y = 0, .z = 0 });
    }
    _ = try world.Build();

    const one_more = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    _ = try AddQuad(engine_context, one_more, .{ .x = 0, .y = 0, .z = 0 });
    try std.testing.expectError(error.TooManyScenes, world.Build());
}

test "an entity destroyed after the build keeps its box through a refit, and the refit reads nothing of it" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const editor_world = &engine_context.mEditorWorld;
    const level = try editor_world.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    const rock = try AddQuad(engine_context, level, .{ .x = 3, .y = 0, .z = 0 });
    const ball = try level.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try ball.AddComponent(engine_context, ColliderComponent{});
    const bvh = try world.Build();
    const tree = &bvh.mGame;
    const rock_box = tree.mBVHItems.items[IndexOf(tree, rock)].Bounds;

    //gone straight away, mid frame, while the tree still names both
    try rock.Delete(engine_context);
    try ball.Delete(engine_context);
    try std.testing.expect(!rock.IsActive());
    bvh.Refit(engine_context, editor_world, WorldBVH.ALL_ITEMS);

    try std.testing.expectEqual(rock_box, tree.mBVHItems.items[IndexOf(tree, rock)].Bounds);
    try ExpectTreeHoldsItems(tree);
}

test "a text's click box is the whole text area, the same box picking tests, and a refit moves it" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const editor_world = &engine_context.mEditorWorld;
    const level = try editor_world.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    const sign = try AddText(engine_context, level, "A A\nAA", .{ .x = 2, .y = 1, .z = 0 });
    const bvh = try world.Build();
    const tree = &bvh.mGame;

    var text_ind: ?usize = null;
    for (tree.mItems.items, 0..) |item, i| {
        if (item.Kind == .Text) text_ind = i;
    }
    const transform = sign.GetComponent(TransformComponent).?;
    const text = sign.GetComponent(TextComponent).?;
    const expected = WorldBVH.BoxBounds(ShapeGeometry.TextBox(TestFont, transform, text, &TEST_FONT, null));
    try std.testing.expectEqual(expected, tree.mBVHItems.items[text_ind.?].Bounds);

    try sign.SetTranslation(engine_context, .{ .x = -20, .y = 1, .z = 0 });
    try PhysicsManager.UpdateWorldTransforms(editor_world, engine_context);
    bvh.Refit(engine_context, editor_world, BVH.Mask.PICK);
    const moved = WorldBVH.BoxBounds(ShapeGeometry.TextBox(TestFont, transform, text, &TEST_FONT, null));
    try std.testing.expectEqual(moved, tree.mBVHItems.items[text_ind.?].Bounds);
}

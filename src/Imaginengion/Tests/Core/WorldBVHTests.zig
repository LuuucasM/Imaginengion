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
const TransformSystem = @import("../../Physics/TransformSystem.zig");
const BVHBuildSystem = @import("../../Core/BVHBuildSystem.zig");
const BVHRefitSystem = @import("../../Core/BVHRefitSystem.zig");
const EngineStats = @import("../../Core/EngineStats.zig");
const Renderer2D = @import("../../Renderer/Renderer2D.zig");
const SDFFunctions = @import("../../Math/SDFFunctions.zig");
const RayIntersect = @import("../../Math/RayIntersect.zig");
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
const MaskComponent = EntityComponents.MaskComponent;
const MainObjectComponent = EntityComponents.MainObjectComponent;

const TestWorld = struct {
    mEngineContext: *EngineContext,

    fn Init() !*TestWorld {
        const self = try std.heap.page_allocator.create(TestWorld);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext) };
        self.mEngineContext.* = .{};
        try self.mEngineContext.mEditorWorld.Init(self.mEngineContext);
        return self;
    }

    fn Deinit(self: *TestWorld) void {
        const engine_context = self.mEngineContext;
        engine_context.mEditorWorld.Deinit(engine_context);
        _ = engine_context._Internal.KeepHeap.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }

    /// WorldManager.BuildBVH, with texts in the stand in font
    fn Build(self: *TestWorld) !*WorldBVH {
        const engine_context = self.mEngineContext;
        const world = &engine_context.mEditorWorld;
        try engine_context.mSystems.RunSystem(TransformSystem, engine_context, .{world});
        try engine_context.mSystems.RunSystem(BVHBuildSystem, engine_context, .{ world, TestFonts{} });
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
    try text_component.SetText(entity.KeepFor(TextComponent), text);
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
    //the text is one item, however many letters it has
    try std.testing.expectEqual(@as(usize, 2), overlay.mItems.items.len);
    try std.testing.expectEqual(@as(usize, 1), ItemsOf(overlay, label));
    try std.testing.expectEqual(@as(usize, 1), ItemsOf(overlay, row_button));

    const Expected = struct { Tree: *const WorldBVH.LayerTree, Entity: Entity, Kind: WorldBVH.ItemKind, Mask: u4 };
    const expected = [_]Expected{
        .{ .Tree = game, .Entity = rock, .Kind = .Quad, .Mask = BVH.Mask.RENDER | BVH.Mask.PICK },
        .{ .Tree = game, .Entity = wall, .Kind = .Collider, .Mask = BVH.Mask.PHYSICS },
        .{ .Tree = game, .Entity = merge, .Kind = .Merge, .Mask = BVH.Mask.RENDER | BVH.Mask.PICK },
        .{ .Tree = overlay, .Entity = row_button, .Kind = .Quad, .Mask = BVH.Mask.PICK },
        //drawn by its letters, clicked anywhere on it
        .{ .Tree = overlay, .Entity = label, .Kind = .Text, .Mask = BVH.Mask.RENDER | BVH.Mask.PICK },
    };
    for (expected) |want| {
        const ind = IndexOf(want.Tree, want.Entity);
        try std.testing.expectEqual(want.Kind, want.Tree.mItems.items[ind].Kind);
        try std.testing.expectEqual(want.Mask, want.Tree.mBVHItems.items[ind].Mask);
    }
    //its two letters, the space drawing nothing
    try std.testing.expectEqual(@as(u32, 2), TextEntryOf(bvh, overlay, label).GlyphCount);

    //each item knows its scene, and a view showing only the HUD names only its slot
    for (game.mItems.items) |item| try std.testing.expectEqual(level.mID, bvh.mScenes.items[item.SceneSlot]);
    for (overlay.mItems.items) |item| try std.testing.expectEqual(hud.mID, bvh.mScenes.items[item.SceneSlot]);
    const hud_slot = overlay.mItems.items[0].SceneSlot;
    try std.testing.expectEqual(@as(u64, 1) << @intCast(hud_slot), bvh.SceneBits(&.{hud.mID}));
    try std.testing.expectEqual(@as(u64, 0b11), bvh.SceneBits(&.{ hud.mID, level.mID }));

    try ExpectTreeHoldsItems(game);
    try ExpectTreeHoldsItems(overlay);
}

test "a text's stand in moves where each letter is placed back to where it is in its layout, at the same distance along a ray" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const level = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    //turned, stretched unevenly and mirrored, with a left bound, over two lines
    const text = try level.CreateEntity(engine_context, Entity.DefaultConfig);
    try text.SetTranslation(engine_context, .{ .x = 3, .y = 2, .z = -1 });
    try text.SetScale(engine_context, .{ .x = 2, .y = -0.5, .z = 1 });
    try text.SetRotation(engine_context, MathTypes.Quat(f32).FromAxisAngle(Unit(.{ .x = 0.3, .y = 0.2, .z = 1 }), 0.7));
    const text_component = try text.AddComponent(engine_context, TextComponent{ .mBounds = .{ .x = 1.5, .y = 6 }, .mFontSize = 1 });
    try text_component.SetText(text.KeepFor(TextComponent), "AAAAAA\nAAAAAA");
    _ = try text.AddComponent(engine_context, SurfaceComponent{});

    const bvh = try world.Build();
    const tree = &bvh.mGame;
    try std.testing.expectEqual(@as(usize, 1), tree.mItems.items.len);
    const entry = TextEntryOf(bvh, tree, text);
    try std.testing.expectEqual(@as(u32, 12), entry.GlyphCount);

    const transform = text.GetComponent(TransformComponent).?;
    const params = ShapeGeometry.GetTextParams(transform, text.GetComponent(TextComponent).?);
    const axes = Renderer2D.TextLayoutAxes(transform.GetWorldPosition(), transform.GetWorldRotation(), params.Stretch, params.LeftBound).?;
    var stand_in: Renderer2D.ShapeData = undefined;
    stand_in.AxisX = axes[0];
    stand_in.AxisY = axes[1];
    stand_in.AxisZ = axes[2];
    const item_box = tree.mBVHItems.items[0].Bounds;
    for (bvh.Letters(entry)) |letter| {
        //where the renderer draws it, inside the text's one box
        const placed = ShapeGeometry.GlyphBox(transform, params, letter, null);
        try std.testing.expect(BoxHolds(item_box.Grow(0.0001), WorldBVH.BoxBounds(placed)));
        //and back in its layout
        try ExpectNear(WorldBVH.LetterBounds(letter).Center(), SDFFunctions.ShapeLocalPoint(stand_in, placed.Center));

        //a ray to it reaches its layout box at the same distance along it as its placed one
        const origin = Vec3(f32){ .x = -2, .y = 1, .z = 9 };
        const dir = Unit(placed.Center.SubVec(origin));
        const placed_bounds = WorldBVH.BoxBounds(placed);
        const world_span = RayIntersect.RayAabb(origin, Inverse(dir), placed_bounds.Min, placed_bounds.Max).?;
        const local_dir = SDFFunctions.ShapeLocalDir(stand_in, dir);
        const layout_box = WorldBVH.LetterBounds(letter);
        const local_span = RayIntersect.RayAabb(SDFFunctions.ShapeLocalPoint(stand_in, origin), Inverse(local_dir), layout_box.Min, layout_box.Max).?;
        //the boxes differ (an axis lined up box around a turned one is bigger), but both hold the center
        const center_t = @sqrt(placed.Center.SubVec(origin).Dot(placed.Center.SubVec(origin)));
        try std.testing.expect(world_span.Enter <= center_t + 0.0001 and local_span.Enter <= center_t + 0.0001);
        try std.testing.expect(local_span.Exit >= center_t - 0.0001);
        try ExpectNear(placed.Center, origin.AddVec(dir.MulScalar(center_t)));
        try ExpectNear(WorldBVH.LetterBounds(letter).Center(), SDFFunctions.ShapeLocalPoint(stand_in, origin).AddVec(local_dir.MulScalar(center_t)));
    }
    try ExpectTreeHoldsItems(tree);
}

fn Unit(v: Vec3(f32)) Vec3(f32) {
    return v.MulScalar(1 / @sqrt(v.Dot(v)));
}

fn Inverse(dir: Vec3(f32)) Vec3(f32) {
    return .{ .x = 1 / dir.x, .y = 1 / dir.y, .z = 1 / dir.z };
}

test "a letter's box in canvas units, placed by a view's canvas, is the box that view draws it with" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const hud = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    const text = try AddText(engine_context, hud, "AA", .{ .x = 120, .y = -40, .z = 0 });
    try text.SetScale(engine_context, .{ .x = 3, .y = 2, .z = 1 });
    try engine_context.mSystems.RunSystem(TransformSystem, engine_context, .{&engine_context.mEditorWorld});

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
    //its letters run past its narrow bounds (one to a line), so its box has to hold them as well as its click area
    const sign = try level.CreateEntity(engine_context, Entity.DefaultConfig);
    try sign.SetTranslation(engine_context, .{ .x = 0, .y = 4, .z = 0 });
    const sign_component = try sign.AddComponent(engine_context, TextComponent{ .mBounds = .{ .x = 0, .y = 0.2 }, .mFontSize = 1 });
    try sign_component.SetText(sign.KeepFor(TextComponent), "AAAAAA");
    _ = try sign.AddComponent(engine_context, SurfaceComponent{});

    const bvh = try world.Build();
    const tree = &bvh.mGame;
    const node_count = tree.mNodes.items.len;

    //far off, past every other box, so the root has to grow to hold them
    const moved = quads[3];
    try moved.SetTranslation(engine_context, .{ .x = 100, .y = -30, .z = 5 });
    try ball.SetTranslation(engine_context, .{ .x = -40, .y = 0, .z = 0 });
    try sign.SetTranslation(engine_context, .{ .x = 0, .y = 60, .z = 0 });
    try engine_context.mSystems.RunSystem(TransformSystem, engine_context, .{editor_world});
    try engine_context.mSystems.RunSystem(BVHRefitSystem, engine_context, .{ editor_world, WorldBVH.ALL_ITEMS });

    //the same tree, its boxes moved
    try std.testing.expectEqual(node_count, tree.mNodes.items.len);
    try ExpectNear(.{ .x = 100, .y = -30, .z = 5 }, tree.mBVHItems.items[IndexOf(tree, moved)].Bounds.Center());
    try ExpectNear(.{ .x = -40, .y = 0, .z = 0 }, tree.mBVHItems.items[IndexOf(tree, ball)].Bounds.Center());
    for (tree.mItems.items, tree.mBVHItems.items) |item, bvh_item| {
        //six one letter lines (it wraps after each), 1.2 apart, down from y 60
        if (item.Entity == sign.mID) try std.testing.expect(bvh_item.Bounds.Min.y > 50);
    }
    //the text's one box still holds every letter where the renderer now places it
    const sign_transform = sign.GetComponent(TransformComponent).?;
    const sign_params = ShapeGeometry.GetTextParams(sign_transform, sign.GetComponent(TextComponent).?);
    const sign_box = tree.mBVHItems.items[IndexOf(tree, sign)].Bounds;
    for (bvh.Letters(TextEntryOf(bvh, tree, sign))) |letter| {
        try std.testing.expect(BoxHolds(sign_box.Grow(0.0001), WorldBVH.BoxBounds(ShapeGeometry.GlyphBox(sign_transform, sign_params, letter, null))));
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
    try engine_context.mSystems.RunSystem(TransformSystem, engine_context, .{editor_world});
    try engine_context.mSystems.RunSystem(BVHRefitSystem, engine_context, .{ editor_world, BVH.Mask.PHYSICS });

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
    try engine_context.mSystems.RunSystem(BVHRefitSystem, engine_context, .{ editor_world, WorldBVH.ALL_ITEMS });
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
    try engine_context.mSystems.RunSystem(TransformSystem, engine_context, .{editor_world});

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
    try engine_context.mSystems.RunSystem(BVHRefitSystem, engine_context, .{ editor_world, WorldBVH.ALL_ITEMS });

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
    try engine_context.mSystems.RunSystem(TransformSystem, engine_context, .{editor_world});
    try engine_context.mSystems.RunSystem(BVHRefitSystem, engine_context, .{ editor_world, BVH.Mask.PICK });
    const moved = WorldBVH.BoxBounds(ShapeGeometry.TextBox(TestFont, transform, text, &TEST_FONT, null));
    try std.testing.expectEqual(moved, tree.mBVHItems.items[text_ind.?].Bounds);
}

/// The text entry (WorldBVH.TextEntry) of `entity`'s click item
fn TextEntryOf(bvh: *const WorldBVH, tree: *const WorldBVH.LayerTree, entity: Entity) WorldBVH.TextEntry {
    for (tree.mItems.items) |item| {
        if (item.Entity == entity.mID and item.Kind == .Text) return bvh.mTexts.items[item.Index];
    }
    unreachable;
}

test "each text keeps a tree of its own over its letters, in its layout space, split at its line breaks" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const level = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    //ten letters, the only line break past the middle (wide enough not to wrap); then a short one, turned and stretched
    const sign = try level.CreateEntity(engine_context, Entity.DefaultConfig);
    try sign.SetTranslation(engine_context, .{ .x = 3, .y = 2, .z = 0 });
    const sign_text = try sign.AddComponent(engine_context, TextComponent{ .mBounds = .{ .x = 0, .y = 100 }, .mFontSize = 1 });
    try sign_text.SetText(sign.KeepFor(TextComponent), "AAAAAAAA\nAA");
    _ = try sign.AddComponent(engine_context, SurfaceComponent{});
    const label = try AddText(engine_context, level, "AAAAAA", .{ .x = -4, .y = 1, .z = 0.5 });
    try label.SetScale(engine_context, .{ .x = 2, .y = 0.5, .z = 1 });
    try label.SetRotation(engine_context, MathTypes.Quat(f32).FromAxisAngle(.{ .x = 0, .y = 0, .z = 1 }, 0.4));

    const bvh = try world.Build();
    const tree = &bvh.mGame;
    var total_nodes: u32 = 0;
    for ([_]Entity{ sign, label }, [_]u32{ 10, 6 }) |entity, letter_count| {
        const entry = TextEntryOf(bvh, tree, entity);
        try std.testing.expectEqual(letter_count, entry.GlyphCount);
        const letters = bvh.Letters(entry);
        const nodes = bvh.LetterTree(entry);
        total_nodes += entry.NodeCount;

        //a tree of its own: its root's Skip is its end, and its leaves cover its letters in order, each box around
        //its letters' layout boxes
        try std.testing.expectEqual(entry.NodeCount, nodes[0].Skip);
        var next_letter: u32 = 0;
        for (nodes) |node| {
            if (!node.IsLeaf()) continue;
            try std.testing.expectEqual(next_letter, node.FirstItem());
            for (letters[node.FirstItem()..][0..node.ItemCount()]) |letter| {
                try std.testing.expect(BoxHolds(node.Bounds(), WorldBVH.LetterBounds(letter)));
            }
            next_letter += node.ItemCount();
        }
        try std.testing.expectEqual(letter_count, next_letter);

        //its root, placed by the text's transform, holds every letter where the renderer places it, and the text's one
        //item holds that
        const transform = entity.GetComponent(TransformComponent).?;
        const params = ShapeGeometry.GetTextParams(transform, entity.GetComponent(TextComponent).?);
        const root = nodes[0].Bounds();
        const ink = WorldBVH.BoxBounds(ShapeGeometry.TextInkBox(transform, params, .{ .x = root.Min.x, .y = root.Min.y }, .{ .x = root.Max.x, .y = root.Max.y }, null));
        for (letters) |letter| {
            try std.testing.expect(BoxHolds(ink.Grow(0.0001), WorldBVH.BoxBounds(ShapeGeometry.GlyphBox(transform, params, letter, null))));
        }
        try std.testing.expect(BoxHolds(tree.mBVHItems.items[IndexOf(tree, entity)].Bounds, ink));
    }
    //the sign's first split is at its second line
    const sign_nodes = bvh.LetterTree(TextEntryOf(bvh, tree, sign));
    var first_right = sign_nodes[0].RightChild();
    while (!sign_nodes[first_right].IsLeaf()) first_right += 1;
    try std.testing.expectEqual(@as(u32, 8), sign_nodes[first_right].FirstItem());

    var stats = EngineStats.WorldBVHStats{};
    stats.Collect(bvh.*);
    try std.testing.expectEqual(@as(u32, 2), stats.LetterTrees);
    try std.testing.expectEqual(total_nodes, stats.LetterNodes);
}

/// A mask (MaskComponent) `size` across at `position`, cutting with its quad. Its own quad isn't drawn
fn AddMask(engine_context: *EngineContext, parent: anytype, position: Vec3(f32), size: Vec2(f32), op: @import("../../Renderer/SDFProgram.zig").MaskOp) !Entity {
    const mask = try NewEntityIn(engine_context, parent);
    try mask.SetTranslation(engine_context, position);
    _ = try mask.AddComponent(engine_context, ShapeComponent.MakeQuad(.{ .Size = size }));
    _ = try mask.AddComponent(engine_context, MaskComponent{ .mOp = op });
    return mask;
}

/// A new entity in a scene, or under another entity
fn NewEntityIn(engine_context: *EngineContext, parent: anytype) !Entity {
    return switch (@TypeOf(parent)) {
        Scene => parent.CreateEntity(engine_context, Entity.DefaultConfig),
        Entity => parent.CreateChild(engine_context, .Entity, Entity.DefaultConfig),
        else => @compileError("a scene or an entity"),
    };
}

/// A drawn unit quad under `parent`, at `position` from it
fn AddChildQuad(engine_context: *EngineContext, parent: Entity, position: Vec3(f32)) !Entity {
    const quad = try NewEntityIn(engine_context, parent);
    try quad.SetTranslation(engine_context, position);
    _ = try quad.AddComponent(engine_context, ShapeComponent{});
    _ = try quad.AddComponent(engine_context, SurfaceComponent{});
    return quad;
}

/// A drawn text at font size 1 under `parent`, at `position` from it, its lines starting right there (no room left of it) and only
/// wrapping past `width`
fn AddChildText(engine_context: *EngineContext, parent: Entity, text: []const u8, position: Vec3(f32), width: f32) !Entity {
    const entity = try NewEntityIn(engine_context, parent);
    try entity.SetTranslation(engine_context, position);
    const text_component = try entity.AddComponent(engine_context, TextComponent{ .mBounds = .{ .x = 0, .y = width }, .mFontSize = 1 });
    try text_component.SetText(entity.KeepFor(TextComponent), text);
    _ = try entity.AddComponent(engine_context, SurfaceComponent{});
    return entity;
}

/// How far from a 4 x 4 mask's middle what it cuts still goes in the tree, on x and on y: its own half size, grown by
/// the build's margin on both sides
const MASK_SIZE = 4;
const MASK_REACH: f32 = MASK_SIZE / 2 * (1 + 2 * BVHBuildSystem.CULL_MARGIN);

test "what a mask cuts off well past its edge gets no items, quads and texts both, and what is near it keeps them" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const level = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    const mask = try AddMask(engine_context, level, .{ .x = 0, .y = 0, .z = 0 }, .{ .x = MASK_SIZE, .y = MASK_SIZE }, .Intersect);
    const inside = try AddChildQuad(engine_context, mask, .{ .x = 0, .y = 0, .z = 1 });
    //cut off when drawn, but close enough that scrolling it in this frame won't leave a gap
    const near = try AddChildQuad(engine_context, mask, .{ .x = MASK_REACH - 1, .y = 0, .z = 1 });
    const far = try AddChildQuad(engine_context, mask, .{ .x = MASK_REACH + 1, .y = 0, .z = 1 });
    const far_below = try AddChildQuad(engine_context, mask, .{ .x = 0, .y = -MASK_REACH - 1, .z = 1 });
    const far_text = try AddChildText(engine_context, mask, "AA AA", .{ .x = 0, .y = -MASK_REACH - 2, .z = 1 }, 16);
    const near_text = try AddChildText(engine_context, mask, "AA AA", .{ .x = 0, .y = MASK_REACH - 1.5, .z = 1 }, 16);

    const bvh = try world.Build();
    const tree = &bvh.mGame;
    try std.testing.expectEqual(@as(usize, 1), ItemsOf(tree, inside));
    try std.testing.expectEqual(@as(usize, 1), ItemsOf(tree, near));
    try std.testing.expectEqual(@as(usize, 0), ItemsOf(tree, far));
    try std.testing.expectEqual(@as(usize, 0), ItemsOf(tree, far_below));
    //no letters, and no click box either
    try std.testing.expectEqual(@as(usize, 0), ItemsOf(tree, far_text));
    //one item for its letters and its click box
    try std.testing.expectEqual(@as(usize, 1), ItemsOf(tree, near_text));
    //only the text near it has letters, and a tree over them
    try std.testing.expectEqual(@as(usize, 1), bvh.mTexts.items.len);
    try std.testing.expectEqual(@as(u32, 4), TextEntryOf(bvh, tree, near_text).GlyphCount);
    try ExpectTreeHoldsItems(tree);
}

test "a text across a mask's edge keeps every letter in its tree, and one item for drawing and clicking" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const level = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    const mask = try AddMask(engine_context, level, .{ .x = 0, .y = 0, .z = 0 }, .{ .x = MASK_SIZE, .y = MASK_SIZE }, .Intersect);
    //twenty letters on one line, starting a little right of the mask's middle and running far past its room
    const start = 0.1;
    const line = try AddChildText(engine_context, mask, "AAAAAAAAAAAAAAAAAAAA", .{ .x = start, .y = 0, .z = 1 }, 100);

    const bvh = try world.Build();
    const tree = &bvh.mGame;
    //the renderer leaves out the letters its mask cuts off
    try std.testing.expectEqual(@as(usize, 1), ItemsOf(tree, line));
    try std.testing.expectEqual(BVH.Mask.RENDER | BVH.Mask.PICK, tree.mBVHItems.items[IndexOf(tree, line)].Mask);
    try std.testing.expectEqual(@as(u32, 20), TextEntryOf(bvh, tree, line).GlyphCount);
    //reaching past the room, the way its letters do
    try std.testing.expect(tree.mBVHItems.items[IndexOf(tree, line)].Bounds.Max.x > MASK_REACH + start);
    try ExpectTreeHoldsItems(tree);
}

test "a subtract mask, or one with no shape, leaves everything under it in the tree, however far off" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const level = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    const hole = try AddMask(engine_context, level, .{ .x = 0, .y = 0, .z = 0 }, .{ .x = MASK_SIZE, .y = MASK_SIZE }, .Subtract);
    const under_hole = try AddChildQuad(engine_context, hole, .{ .x = 50, .y = 0, .z = 1 });
    const shapeless = try level.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try shapeless.AddComponent(engine_context, MaskComponent{});
    const under_nothing = try AddChildQuad(engine_context, shapeless, .{ .x = 0, .y = 50, .z = 1 });

    const bvh = try world.Build();
    try std.testing.expectEqual(@as(usize, 1), ItemsOf(&bvh.mGame, under_hole));
    try std.testing.expectEqual(@as(usize, 1), ItemsOf(&bvh.mGame, under_nothing));
}

test "a mask inside another cuts off by both: far from the outer one is out, however big the inner one is" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const level = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    const outer = try AddMask(engine_context, level, .{ .x = 0, .y = 0, .z = 0 }, .{ .x = MASK_SIZE, .y = MASK_SIZE }, .Intersect);
    const inner = try AddMask(engine_context, outer, .{ .x = 0, .y = 0, .z = 1 }, .{ .x = 200, .y = 200 }, .Intersect);
    const kept = try AddChildQuad(engine_context, inner, .{ .x = 0, .y = 0, .z = 1 });
    const out_of_outer = try AddChildQuad(engine_context, inner, .{ .x = 0, .y = MASK_REACH + 5, .z = 1 });
    //under the outer one straight, after the inner one has been met: the outer mask's room is its own, not the inner's
    const beside_inner = try AddChildQuad(engine_context, outer, .{ .x = MASK_REACH + 5, .y = 0, .z = 1 });

    const bvh = try world.Build();
    try std.testing.expectEqual(@as(usize, 1), ItemsOf(&bvh.mGame, kept));
    try std.testing.expectEqual(@as(usize, 0), ItemsOf(&bvh.mGame, out_of_outer));
    try std.testing.expectEqual(@as(usize, 0), ItemsOf(&bvh.mGame, beside_inner));
}

test "a refit places its items on the job pool, a run of them per task, and comes out the same as one on this thread" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const editor_world = &engine_context.mEditorWorld;
    const level = try editor_world.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    //quads in a grid, enough that every thread of the pool takes some
    const count = 2000;
    const quads = try std.testing.allocator.alloc(Entity, count);
    defer std.testing.allocator.free(quads);
    for (quads, 0..) |*quad, i| quad.* = try AddQuad(engine_context, level, .{ .x = @floatFromInt(i % 64), .y = @floatFromInt(i / 64), .z = 0 });
    const bvh = try world.Build();
    const tree = &bvh.mGame;

    //a few moved, then every box worked out on this thread to compare against
    const moved = [_]Entity{ quads[5], quads[1031], quads[count - 1] };
    for (moved, 0..) |quad, i| try quad.SetTranslation(engine_context, .{ .x = -50 - @as(f32, @floatFromInt(i)) * 10, .y = 200, .z = 3 });
    try engine_context.mSystems.RunSystem(TransformSystem, engine_context, .{editor_world});
    try engine_context.mSystems.RunSystem(BVHRefitSystem, engine_context, .{ editor_world, WorldBVH.ALL_ITEMS });
    const serial = try std.testing.allocator.dupe(@TypeOf(tree.mBVHItems.items[0]), tree.mBVHItems.items);
    defer std.testing.allocator.free(serial);

    //the same refit on a pool of 3 workers besides this thread
    const threads = try std.heap.page_allocator.create(std.Io.Threaded);
    threads.* = std.Io.Threaded.init(std.heap.page_allocator, .{ .async_limit = .limited(3), .concurrent_limit = .nothing });
    defer {
        engine_context.mJobPool = .{};
        threads.deinit();
        std.heap.page_allocator.destroy(threads);
        engine_context._Internal.ThreadScratchArenas.Deinit();
    }
    engine_context.mJobPool = .{ .mIo = threads.io(), .mWorkers = 3 };
    engine_context._Internal.ThreadScratchArenas.mMainThread = std.Thread.getCurrentId();
    //back where they were, so the refit has something to put right
    for (tree.mBVHItems.items) |*item| item.Bounds = .{ .Min = .{ .x = 0, .y = 0, .z = 0 }, .Max = .{ .x = 0, .y = 0, .z = 0 } };
    try engine_context.mSystems.RunSystem(BVHRefitSystem, engine_context, .{ editor_world, WorldBVH.ALL_ITEMS });

    for (serial, tree.mBVHItems.items) |expected, actual| {
        try ExpectNear(expected.Bounds.Min, actual.Bounds.Min);
        try ExpectNear(expected.Bounds.Max, actual.Bounds.Max);
    }
    try ExpectTreeHoldsItems(tree);
    try std.testing.expect(tree.mBVHItems.items[IndexOf(tree, moved[2])].Bounds.Contains(.{ .x = -70, .y = 200, .z = 3 }));
}

test "the build's table of what each entity is under answers the same as climbing its parents, in any order asked" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const editor_world = &engine_context.mEditorWorld;
    const level = try editor_world.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);

    var prng = std.Random.DefaultPrng.init(0xA2CE);
    const random = prng.random();
    //a random forest: a few roots, every other entity under one made before it, so chains run deep and branch
    var entities: std.ArrayList(Entity) = .empty;
    defer entities.deinit(std.testing.allocator);
    for (0..400) |i| {
        const entity = if (i < 4 or random.uintLessThan(u32, 12) == 0)
            try level.CreateEntity(engine_context, Entity.DefaultConfig)
        else
            try entities.items[random.uintLessThan(usize, entities.items.len)].CreateChild(engine_context, .Entity, Entity.DefaultConfig);
        //quads and merges are what MergeRootOf answers for, masks of both kinds, and main objects that stop a merge
        if (random.uintLessThan(u32, 2) == 0) _ = try entity.AddComponent(engine_context, ShapeComponent{});
        if (random.uintLessThan(u32, 6) == 0) _ = try entity.AddComponent(engine_context, MergeComponent{});
        if (random.uintLessThan(u32, 8) == 0) _ = try entity.AddComponent(engine_context, MaskComponent{ .mOp = if (random.boolean()) .Intersect else .Subtract });
        if (!entity.HasComponent(MainObjectComponent) and random.uintLessThan(u32, 10) == 0) _ = try entity.AddComponent(engine_context, MainObjectComponent{});
        try entities.append(std.testing.allocator, entity);
    }

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var merges: usize = 0;
    var masks: usize = 0;
    for (0..3) |_| {
        //a new table each time, asked in a new order, so climbs start at every depth
        var ancestry = try BVHBuildSystem.Ancestry.Init(arena.allocator(), editor_world);
        random.shuffle(Entity, entities.items);
        for (entities.items) |entity| {
            const merge = try ancestry.MergeRootOf(entity);
            const expected_merge = ShapeGeometry.MergeRootOf(entity);
            try std.testing.expectEqual(if (expected_merge) |e| e.mID else null, if (merge) |e| e.mID else null);
            const mask = try ancestry.MaskRegionAbove(entity);
            const expected_mask = ShapeGeometry.MaskRegionAbove(entity);
            try std.testing.expectEqual(if (expected_mask) |e| e.mID else null, if (mask) |e| e.mID else null);
            if (merge != null) merges += 1;
            if (mask != null) masks += 1;
        }
    }
    //the answers weren't all empty
    try std.testing.expect(merges > 30 and masks > 30);
}

//! A scene's layer is its GameLayerTag or OverlayLayerTag, and every entity in it carries the same one,
//! so the renderer and picking can ask for one layer's shapes with a plain query.
//! Saving, loading and templates are covered in SerializerTests and TmplTests.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");

const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const SceneComponents = @import("../../ECSComponents/SComponents.zig");
const GameLayerTag = EntityComponents.GameLayerTag;
const OverlayLayerTag = EntityComponents.OverlayLayerTag;
const QuadComponent = EntityComponents.QuadComponent;

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

test "a new scene carries the tag of its layer and nothing else" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const game = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const overlay = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);

    try std.testing.expect(game.HasComponent(SceneComponents.GameLayerTag));
    try std.testing.expect(!game.HasComponent(SceneComponents.OverlayLayerTag));
    try std.testing.expectEqual(.GameLayer, game.GetLayer());

    try std.testing.expect(overlay.HasComponent(SceneComponents.OverlayLayerTag));
    try std.testing.expect(!overlay.HasComponent(SceneComponents.GameLayerTag));
    try std.testing.expectEqual(.OverlayLayer, overlay.GetLayer());

    //the tag is the query for a layer's scenes too
    const overlay_scenes = try engine_context.mEditorWorld.GetSceneGroup(engine_context.FrameAllocator(), .{ .Component = SceneComponents.OverlayLayerTag });
    try std.testing.expectEqual(@as(usize, 1), overlay_scenes.items.len);
    try std.testing.expectEqual(overlay.mID, overlay_scenes.items[0]);
}

test "entities take their scene's layer, and so do their children and duplicates" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const game = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const overlay = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);

    const rock = try game.CreateEntity(engine_context, Entity.DefaultConfig);
    const button = try overlay.CreateEntity(engine_context, Entity.DefaultConfig);
    const label = try button.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
    const copy = try button.Duplicate(engine_context);

    try std.testing.expectEqual(.GameLayer, rock.GetLayer());
    try std.testing.expect(!rock.HasComponent(OverlayLayerTag));

    for ([_]Entity{ button, label, copy }) |entity| {
        try std.testing.expectEqual(.OverlayLayer, entity.GetLayer());
        try std.testing.expect(!entity.HasComponent(GameLayerTag));
    }
}

test "a layer query only finds that layer's shapes" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const game = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const overlay = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);

    const rock = try game.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try rock.AddComponent(engine_context, QuadComponent{});
    const button = try overlay.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try button.AddComponent(engine_context, QuadComponent{});
    //no quad, so neither query should find it
    _ = try overlay.CreateEntity(engine_context, Entity.DefaultConfig);

    const game_quads = try engine_context.mEditorWorld.GetEntityGroup(engine_context.FrameAllocator(), .{ .And = &.{
        .{ .Component = QuadComponent },
        .{ .Component = GameLayerTag },
    } });
    try std.testing.expectEqual(@as(usize, 1), game_quads.items.len);
    try std.testing.expectEqual(rock.mID, game_quads.items[0]);

    const overlay_quads = try engine_context.mEditorWorld.GetEntityGroup(engine_context.FrameAllocator(), .{ .And = &.{
        .{ .Component = QuadComponent },
        .{ .Component = OverlayLayerTag },
    } });
    try std.testing.expectEqual(@as(usize, 1), overlay_quads.items.len);
    try std.testing.expectEqual(button.mID, overlay_quads.items[0]);
}

//! The play preview's views (EditorProgram.SyncViewQuads, which the viewport uses too): a viewport quad per view, made
//! and deleted as views come and go, each placed by its camera's area rect in the area's last laid out size (split
//! screen side by side), and the area hidden while the preview is off. No window or renderer needed. Run with
//! `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const Player = @import("../../ECSObjects/Player.zig");
const EditorProgram = @import("../../Programs/EditorProgram.zig");
const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const LayoutComponent = EntityComponents.LayoutComponent;
const LayoutItemComponent = EntityComponents.LayoutItemComponent;
const ViewportComponent = EntityComponents.ViewportComponent;

test "a quad per view placed by its area rect, made and deleted as views come and go, and hidden with the preview" {
    const engine_context = try std.heap.page_allocator.create(EngineContext);
    defer std.heap.page_allocator.destroy(engine_context);
    engine_context.* = .{};
    try engine_context.mUIManager.Init(engine_context.EngineAllocator());
    try engine_context.mEditorWorld.Init(engine_context.EngineAllocator());
    try engine_context.mGameWorld.Init(engine_context.EngineAllocator());
    defer {
        engine_context.mGameWorld.Deinit(engine_context);
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mUIManager.Deinit(engine_context);
        _ = engine_context._Internal.EngineGPA.deinit();
    }
    const ui_scene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    const area = try ui_scene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try area.AddComponent(engine_context, LayoutComponent{});
    //as the area was last laid out
    (try area.AddComponent(engine_context, LayoutItemComponent{})).mComputedSize = .{ .x = 800, .y = 400 };
    var quads: std.ArrayList(Entity) = .empty;
    defer quads.deinit(engine_context.EngineAllocator());

    const one = try engine_context.mGameWorld.CreatePlayer(engine_context, Player.DefaultConfig);
    const two = try engine_context.mGameWorld.CreatePlayer(engine_context, Player.DefaultConfig);
    //split screen: one on the left half, two on the right
    try EditorProgram.SyncViewQuads(engine_context, area, &quads, &.{
        .{ .Player = one, .Area = .{ .x = 0, .y = 0, .z = 0.5, .w = 1 } },
        .{ .Player = two, .Area = .{ .x = 0.5, .y = 0, .z = 0.5, .w = 1 } },
    }, true, "Play View");
    try std.testing.expectEqual(@as(usize, 2), quads.items.len);
    try std.testing.expectEqual(two.mID, quads.items[1].GetComponent(ViewportComponent).?.mPlayer.mID);
    const right = quads.items[1].GetComponent(LayoutItemComponent).?;
    try std.testing.expectEqual(@as(f32, 400), right.mWidth.Fixed);
    try std.testing.expectEqual(@as(f32, 400), right.mHeight.Fixed);
    try std.testing.expectEqual(@as(f32, 400), right.mPlacement.Anchored.Offset.x);

    //one view left: the spare quad goes, the other now fills the area
    try EditorProgram.SyncViewQuads(engine_context, area, &quads, &.{
        .{ .Player = one, .Area = .{ .x = 0, .y = 0, .z = 1, .w = 1 } },
    }, true, "Play View");
    try std.testing.expectEqual(@as(usize, 1), quads.items.len);
    try std.testing.expectEqual(@as(f32, 800), quads.items[0].GetComponent(LayoutItemComponent).?.mWidth.Fixed);

    //the preview off: no views, and the area folded away
    try EditorProgram.SyncViewQuads(engine_context, area, &quads, &.{}, false, "Play View");
    try std.testing.expectEqual(@as(usize, 0), quads.items.len);
    try std.testing.expect(area.GetComponent(LayoutItemComponent).?.mCollapsed);
}

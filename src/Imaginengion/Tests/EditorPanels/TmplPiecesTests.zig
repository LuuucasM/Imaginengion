//! The tree a template edit window shows: a hierarchy tree of only the objects it is handed (HierarchyPanel
//! BuildForRoots), with its own selection, no menu of its own and no Delete on its top rows. The template preview
//! (TmplPreview) isn't tested here: its camera player's render target makes a GPU texture as soon as it exists. Run with
//! `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const HierarchyPanel = @import("../../EditorPanels/HierarchyPanel.zig").HierarchyPanel;
const SelectedObject = @import("../../Programs/EditorProgram.zig").SelectedObject;

const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const LayoutComponent = EntityComponents.LayoutComponent;
const DisabledTag = EntityComponents.DisabledTag;

const TestWorld = struct {
    mEngineContext: *EngineContext,
    mUIScene: Scene = undefined,
    mPage: Entity = .uninit,

    fn Init() !*TestWorld {
        const self = try std.heap.page_allocator.create(TestWorld);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext) };
        const engine_context = self.mEngineContext;
        engine_context.* = .{};
        try engine_context.mUIManager.Init(engine_context.EngineAllocator());
        try engine_context.mEditorWorld.Init(engine_context.EngineAllocator());
        try engine_context.mTmplEditWorld.Init(engine_context.EngineAllocator());
        self.mUIScene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
        self.mPage = try self.mUIScene.CreateEntity(engine_context, Entity.DefaultConfig);
        _ = try self.mPage.AddComponent(engine_context, LayoutComponent{ .mDirection = .Column });
        return self;
    }

    fn Deinit(self: *TestWorld) void {
        const engine_context = self.mEngineContext;
        engine_context.mTmplEditWorld.Deinit(engine_context);
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mUIManager.Deinit(engine_context);
        _ = engine_context._Internal.EngineGPA.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }
};

test "a tree of only the roots it is handed, with no menu of its own and no Delete on a root" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const tmpl_scene = try engine_context.mTmplEditWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const root = try tmpl_scene.CreateEntity(engine_context, Entity.DefaultConfig);
    const child = try root.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
    //another top level entity in the same world, which this tree isn't showing
    _ = try tmpl_scene.CreateEntity(engine_context, Entity.DefaultConfig);

    var tree = try HierarchyPanel(Entity).BuildForRoots(engine_context, world.mPage, .{ .StockScripts = false });
    defer tree.Deinit(engine_context.EngineAllocator());
    var selected: ?SelectedObject = null;
    try tree.UpdateRoots(engine_context, &.{root}, selected);
    try std.testing.expectEqual(@as(usize, 2), tree.mRows.items.len);
    try std.testing.expectEqual(root.mID, tree.mRows.items[0].Object.mID);
    try std.testing.expectEqual(child.mID, tree.mRows.items[1].Object.mID);
    try std.testing.expectEqual(@as(usize, 0), tree.mAreaItems.items.len);

    //its own selection, not the editor's
    try tree.Run(engine_context, tree.ActionOf(tree.mRows.items[1].Header).?, &engine_context.mTmplEditWorld, &selected);
    try std.testing.expectEqual(child.mID, selected.?.entity.mID);

    const Delete = struct {
        fn IsDisabled(panel: anytype) bool {
            for (panel.mRowItems.items) |item| {
                if (item.Action == .Delete) return item.Item.HasComponent(DisabledTag);
            }
            unreachable;
        }
    };
    try tree.OnRightClick(engine_context, tree.mRows.items[0].Header);
    try std.testing.expect(Delete.IsDisabled(tree));
    try tree.OnRightClick(engine_context, tree.mRows.items[1].Header);
    try std.testing.expect(!Delete.IsDisabled(tree));
}

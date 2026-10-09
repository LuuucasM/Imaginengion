//! The hierarchy panels in the editor's own UI (EditorPanels/HierarchyPanel.zig): the tree of a world's objects with
//! children under their parents and scenes in stack order, rows following renames, built again when the tree's shape
//! changes with its open nodes kept open, a click selecting and the selected row highlighted however it was selected,
//! rows carrying their object to drag, the row menu acting on the row it was opened on, and the panel's own menu.
//! No window or renderer needed. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const UIManager = @import("../../UI/UIManager.zig");
const HierarchyPanel = @import("../../EditorPanels/HierarchyPanel.zig").HierarchyPanel;
const SelectedObject = @import("../../Programs/EditorProgram.zig").SelectedObject;

const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const TextComponent = EntityComponents.TextComponent;
const LayoutComponent = EntityComponents.LayoutComponent;
const LayoutItemComponent = EntityComponents.LayoutItemComponent;
const SelectedTag = EntityComponents.SelectedTag;
const DisabledTag = EntityComponents.DisabledTag;
const DragSourceComponent = EntityComponents.DragSourceComponent;
const ObjectRefComponent = EntityComponents.ObjectRefComponent;

const TestWorld = struct {
    mEngineContext: *EngineContext,
    mPage: Entity = .uninit,

    fn Init() !*TestWorld {
        const self = try std.heap.page_allocator.create(TestWorld);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext) };
        const engine_context = self.mEngineContext;
        engine_context.* = .{};
        try engine_context.mUIManager.Init(engine_context.EngineAllocator());
        try engine_context.mEditorWorld.Init(engine_context.EngineAllocator());
        try engine_context.mGameWorld.Init(engine_context.EngineAllocator());
        const ui_scene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
        //the shell's tab page
        self.mPage = try ui_scene.CreateEntity(engine_context, Entity.DefaultConfig);
        _ = try self.mPage.AddComponent(engine_context, LayoutComponent{ .mDirection = .Column });
        return self;
    }

    fn Deinit(self: *TestWorld) void {
        const engine_context = self.mEngineContext;
        engine_context.mGameWorld.Deinit(engine_context);
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mUIManager.Deinit(engine_context);
        _ = engine_context._Internal.EngineGPA.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }

    fn Panel(self: *TestWorld, comptime T: type) !HierarchyPanel(T) {
        return try HierarchyPanel(T).Build(self.mEngineContext, self.mPage, .{ .StockScripts = false });
    }
};

fn Names(panel: anytype, out: [][]const u8) usize {
    for (panel.mRows.items, 0..) |row, i| {
        if (i < out.len) out[i] = row.Label.GetComponent(TextComponent).?.mText.items;
    }
    return panel.mRows.items.len;
}

test "entities under their parents, scenes top layer first, and rows following renames" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const game_world = &engine_context.mGameWorld;
    const level = try game_world.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const hero = try level.CreateEntity(engine_context, Entity.DefaultConfig);
    try hero.SetName(engine_context, "Hero");
    const sword = try hero.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
    try sword.SetName(engine_context, "Sword");

    var entities = try world.Panel(Entity);
    defer entities.Deinit(engine_context.EngineAllocator());
    try entities.Update(engine_context, game_world, null);
    var names: [8][]const u8 = undefined;
    try std.testing.expectEqual(@as(usize, 2), Names(entities, &names));
    try std.testing.expectEqualStrings("Hero", names[0]);
    try std.testing.expectEqualStrings("Sword", names[1]);
    //Hero is a node with Sword in it, Sword a leaf
    try std.testing.expect(entities.mRows.items[0].Content != null);
    try std.testing.expect(entities.mRows.items[1].Content == null);

    //renamed: the text follows, the tree isn't built again
    const tree = entities.mTree.?;
    try hero.SetName(engine_context, "Knight");
    try entities.Update(engine_context, game_world, null);
    try std.testing.expectEqual(tree.mID, entities.mTree.?.mID);
    _ = Names(entities, &names);
    try std.testing.expectEqualStrings("Knight", names[0]);

    //a second game scene and an overlay: the top of the stack first
    const hud = try game_world.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
    try hud.SetName(engine_context, "HUD");
    try level.SetName(engine_context, "Level");
    var scenes = try world.Panel(Scene);
    defer scenes.Deinit(engine_context.EngineAllocator());
    try scenes.Update(engine_context, game_world, null);
    try std.testing.expectEqual(@as(usize, 2), Names(scenes, &names));
    try std.testing.expectEqualStrings("HUD", names[0]);
    try std.testing.expectEqualStrings("Level", names[1]);
}

test "a new object builds the tree again with open nodes still open, and rows carry their object to drag" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const game_world = &engine_context.mGameWorld;
    const level = try game_world.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const hero = try level.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try hero.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
    var entities = try world.Panel(Entity);
    defer entities.Deinit(engine_context.EngineAllocator());
    try entities.Update(engine_context, game_world, null);

    //Hero's node opened, then another entity made
    entities.mRows.items[0].Content.?.GetComponent(LayoutItemComponent).?.mCollapsed = false;
    const tree = entities.mTree.?;
    _ = try level.CreateEntity(engine_context, Entity.DefaultConfig);
    try entities.Update(engine_context, game_world, null);
    try std.testing.expect(entities.mTree.?.mID != tree.mID);
    try std.testing.expectEqual(@as(usize, 3), entities.mRows.items.len);
    try std.testing.expect(!entities.mRows.items[0].Content.?.GetComponent(LayoutItemComponent).?.mCollapsed);

    const header = entities.mRows.items[0].Header;
    try std.testing.expect(header.HasComponent(DragSourceComponent));
    try std.testing.expectEqual(hero.mID, header.GetComponent(ObjectRefComponent).?.mObject.entity.mID);
}

test "a click selects, and the selected object's row is highlighted however it was selected" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const game_world = &engine_context.mGameWorld;
    const level = try game_world.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const hero = try level.CreateEntity(engine_context, Entity.DefaultConfig);
    const villain = try level.CreateEntity(engine_context, Entity.DefaultConfig);
    var entities = try world.Panel(Entity);
    defer entities.Deinit(engine_context.EngineAllocator());
    try entities.Update(engine_context, game_world, null);

    var selected: ?SelectedObject = null;
    const villain_row = for (entities.mRows.items) |row| {
        if (row.Object.mID == villain.mID) break row;
    } else unreachable;
    try entities.Run(engine_context, entities.ActionOf(villain_row.Header).?, game_world, &selected);
    try std.testing.expectEqual(villain.mID, selected.?.entity.mID);
    try entities.Update(engine_context, game_world, selected);
    try std.testing.expect(villain_row.Header.HasComponent(SelectedTag));

    //selected somewhere else (the viewport): the highlight moves with it, and goes when it isn't an entity
    try entities.Update(engine_context, game_world, .{ .entity = hero });
    try std.testing.expect(!villain_row.Header.HasComponent(SelectedTag));
    try entities.Update(engine_context, game_world, .{ .scene_layer = level });
    for (entities.mRows.items) |row| try std.testing.expect(!row.Header.HasComponent(SelectedTag));
}

test "the row menu acts on the row it was opened on, and the panel's menu makes new objects" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const game_world = &engine_context.mGameWorld;
    const level = try game_world.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
    const hero = try level.CreateEntity(engine_context, Entity.DefaultConfig);
    var entities = try world.Panel(Entity);
    defer entities.Deinit(engine_context.EngineAllocator());
    var selected: ?SelectedObject = null;
    try entities.Update(engine_context, game_world, selected);

    //right clicked on Hero: no project is open, so no Make Template
    try entities.OnRightClick(engine_context, entities.mRows.items[0].Header);
    for (entities.mRowItems.items) |item| {
        if (item.Action == .MakeTemplate) try std.testing.expect(item.Item.HasComponent(DisabledTag));
    }
    try entities.Run(engine_context, .NewChild, game_world, &selected);
    var children = hero.GetIterator(.Child);
    try std.testing.expect(children.next() != null);

    //New Entity needs a scene selected
    try std.testing.expect(entities.mAreaItems.items[0].Item.HasComponent(DisabledTag));
    selected = .{ .scene_layer = level };
    try entities.Update(engine_context, game_world, selected);
    try std.testing.expect(!entities.mAreaItems.items[0].Item.HasComponent(DisabledTag));
    try entities.Run(engine_context, .New, game_world, &selected);
    try entities.Update(engine_context, game_world, selected);
    try std.testing.expectEqual(@as(usize, 3), entities.mRows.items.len);

    var scenes = try world.Panel(Scene);
    defer scenes.Deinit(engine_context.EngineAllocator());
    try scenes.Run(engine_context, .NewOverlay, game_world, &selected);
    try scenes.Update(engine_context, game_world, selected);
    try std.testing.expectEqual(@as(usize, 2), scenes.mRows.items.len);
    try std.testing.expectEqual(.OverlayLayer, scenes.mRows.items[0].Object.GetLayer());
}

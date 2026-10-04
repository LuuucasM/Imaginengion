//! Trees and menus (UI/Widgets.zig builders, UI/WidgetActions.zig behaviors) on real entities: selecting across a tree,
//! folding with an arrow, and menus opening, switching and closing the way the stock scripts drive them. The stock scripts
//! are only hooks; they are checked by compiling them, not here. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const UIManager = @import("../../UI/UIManager.zig");
const WidgetActions = @import("../../UI/WidgetActions.zig");
const Widgets = @import("../../UI/Widgets.zig");

const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const SelectedTag = EntityComponents.SelectedTag;
const TextComponent = EntityComponents.TextComponent;
const LayoutItemComponent = EntityComponents.LayoutItemComponent;
const UIComponents = @import("../../ECSComponents/UIComponents.zig");
const StyleComponent = UIComponents.StyleComponent;
const PopupComponent = UIComponents.PopupComponent;

const NO_SCRIPTS = Widgets.Options{ .StockScripts = false };

const TestWorld = struct {
    mEngineContext: *EngineContext,
    mScene: Scene = undefined,
    mPanel: Entity = .uninit,

    fn Init() !*TestWorld {
        const self = try std.heap.page_allocator.create(TestWorld);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext) };
        const engine_context = self.mEngineContext;
        engine_context.* = .{};
        try engine_context.mUIManager.Init(engine_context.EngineAllocator());
        try engine_context.mEditorWorld.Init(engine_context.EngineAllocator());
        self.mScene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
        self.mPanel = try self.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
        return self;
    }

    fn Deinit(self: *TestWorld) void {
        const engine_context = self.mEngineContext;
        engine_context.mPointerSystem.Deinit(engine_context.EngineAllocator());
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mUIManager.Deinit(engine_context);
        _ = engine_context._Internal.EngineGPA.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }

    fn Node(self: *TestWorld, parent: Entity, text: []const u8, leaf: bool) !Widgets.Fold {
        return Widgets.TreeNode(self.mEngineContext, .{ .Entity = parent }, text, .{ .Leaf = leaf, .StockScripts = false });
    }

    fn IsOpen(self: *TestWorld, popup: Entity) bool {
        return self.mEngineContext.mUIManager.mPopupSystem.IsOpen(popup);
    }

    fn OpenCount(self: *TestWorld) usize {
        return self.mEngineContext.mUIManager.mPopupSystem.OpenPopups().len;
    }
};

fn StyleOf(entity: Entity) []const u8 {
    return UIManager.GetUIComponent(entity, StyleComponent).?.mStyle.items;
}

fn Child(entity: Entity, index: usize) Entity {
    var children = entity.GetIterator(.Child);
    var child = children.next().?;
    for (0..index) |_| child = children.next().?;
    return child;
}

fn TextOf(entity: Entity) []const u8 {
    return UIManager.LabelOf(entity).?.GetComponent(TextComponent).?.mText.items;
}

fn ArrowOf(header: Entity) []const u8 {
    return TextOf(Child(header, 0));
}

test "selecting a tree row unselects the row selected in another branch, and leaves checkboxes outside the tree alone" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const tree = try Widgets.Tree(engine_context, .{ .Entity = world.mPanel });
    const player = try world.Node(tree, "Player", false);
    const sword = try world.Node(player.Content.?, "Sword", true);
    const camera = try world.Node(tree, "Camera", true);
    const checkbox = try Widgets.Checkbox(engine_context, .{ .Entity = world.mPanel }, "Grid", NO_SCRIPTS);
    try WidgetActions.Toggle(engine_context, Child(checkbox, 0));

    try WidgetActions.Select(engine_context, sword.Header);
    try WidgetActions.Select(engine_context, camera.Header);
    try std.testing.expect(!sword.Header.HasComponent(SelectedTag));
    try std.testing.expect(camera.Header.HasComponent(SelectedTag));
    try std.testing.expect(Child(checkbox, 0).HasComponent(SelectedTag));

    //without a group, selecting stays among siblings
    const row_a = try Widgets.SelectableRow(engine_context, .{ .Entity = world.mPanel }, "A", NO_SCRIPTS);
    try WidgetActions.Select(engine_context, row_a);
    try std.testing.expect(Child(checkbox, 0).HasComponent(SelectedTag));
    try std.testing.expect(camera.Header.HasComponent(SelectedTag));
}

test "a tree node's arrow folds its content and turns, and a leaf has no arrow and nothing to fold" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const tree = try Widgets.Tree(engine_context, .{ .Entity = world.mPanel });
    const node = try world.Node(tree, "Player", false);
    try std.testing.expectEqualStrings("Header", StyleOf(node.Header));
    try std.testing.expectEqualStrings("Player", TextOf(Child(node.Header, 1)));
    //starts folded
    try std.testing.expectEqualStrings(WidgetActions.ARROW_FOLDED, ArrowOf(node.Header));
    try std.testing.expect(node.Content.?.GetComponent(LayoutItemComponent).?.mCollapsed);
    try std.testing.expectEqual(Widgets.INDENT, node.Content.?.GetComponent(EntityComponents.LayoutComponent).?.mPadding.Left);

    try WidgetActions.FoldFromArrow(engine_context, Child(node.Header, 0));
    try std.testing.expect(!node.Content.?.GetComponent(LayoutItemComponent).?.mCollapsed);
    try std.testing.expectEqualStrings(WidgetActions.ARROW_OPEN, ArrowOf(node.Header));
    try WidgetActions.FoldNext(engine_context, node.Header);
    try std.testing.expectEqualStrings(WidgetActions.ARROW_FOLDED, ArrowOf(node.Header));

    const leaf = try world.Node(tree, "Camera", true);
    try std.testing.expect(leaf.Content == null);
    //the gap where the arrow would be has nothing in it
    var gap_children = Child(leaf.Header, 0).GetIterator(.Child);
    try std.testing.expect(gap_children.next() == null);
    try WidgetActions.FoldNext(engine_context, leaf.Header);
}

test "a collapsing header folds the content right after it, and folding a header without an arrow leaves its text" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const section = try Widgets.CollapsingHeader(engine_context, .{ .Entity = world.mPanel }, "Transform", true, NO_SCRIPTS);
    try std.testing.expectEqualStrings(WidgetActions.ARROW_OPEN, ArrowOf(section.Header));
    try WidgetActions.FoldNext(engine_context, section.Header);
    try std.testing.expect(section.Content.?.GetComponent(LayoutItemComponent).?.mCollapsed);
    try std.testing.expectEqualStrings(WidgetActions.ARROW_FOLDED, ArrowOf(section.Header));

    const button = try Widgets.Button(engine_context, .{ .Entity = world.mPanel }, "Play");
    _ = try Widgets.Label(engine_context, .{ .Entity = world.mPanel }, "after");
    try WidgetActions.FoldNext(engine_context, button);
    try std.testing.expectEqualStrings("Play", TextOf(button));
}

/// A menu bar with File (New, Recent > ..., Save with a shortcut, Grid checkable) and Edit (Undo)
const Menus = struct {
    Bar: Entity,
    File: Entity,
    Edit: Entity,
    New: Entity,
    Recent: Entity,
    RecentRow: Entity,
    Save: Entity,
    Grid: Entity,
    Undo: Entity,

    fn Make(world: *TestWorld) !Menus {
        const engine_context = world.mEngineContext;
        const bar = try Widgets.MenuBar(engine_context, .{ .Entity = world.mPanel });
        const file = try Widgets.Menu(engine_context, bar, "File", NO_SCRIPTS);
        const edit = try Widgets.Menu(engine_context, bar, "Edit", NO_SCRIPTS);
        const new = try Widgets.MenuItem(engine_context, file, "New", .{ .StockScripts = false });
        const recent = try Widgets.Submenu(engine_context, file, "Recent", NO_SCRIPTS);
        _ = try Widgets.MenuItem(engine_context, recent, "level1", .{ .StockScripts = false });
        _ = try Widgets.Separator(engine_context, .{ .Entity = file });
        const save = try Widgets.MenuItem(engine_context, file, "Save", .{ .Shortcut = "Ctrl+S", .StockScripts = false });
        const grid = try Widgets.MenuItem(engine_context, file, "Grid", .{ .Checkable = true, .StockScripts = false });
        const undo = try Widgets.MenuItem(engine_context, edit, "Undo", .{ .StockScripts = false });
        return .{ .Bar = bar, .File = file, .Edit = edit, .New = new, .Recent = recent, .RecentRow = Child(file, 1), .Save = save, .Grid = grid, .Undo = undo };
    }
};

test "a menu bar's menus are popups its buttons open, and its items have their text, shortcut and check box" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const menus = try Menus.Make(world);

    try std.testing.expectEqualStrings("MenuBar", StyleOf(menus.Bar));
    const file_button = Child(menus.Bar, 0);
    try std.testing.expectEqualStrings("File", TextOf(file_button));
    try std.testing.expectEqual(menus.File.mID, WidgetActions.PopupOf(file_button).?.mID);
    try std.testing.expect(UIManager.HasUIComponent(menus.File, PopupComponent));
    //closed until opened, and in front of the rest of the scene
    try std.testing.expect(menus.File.GetComponent(LayoutItemComponent).?.mCollapsed);

    try std.testing.expectEqualStrings("Ctrl+S", TextOf(Child(menus.Save, 1)));
    try std.testing.expectEqualStrings("TextDim", StyleOf(Child(menus.Save, 1)));
    try std.testing.expectEqualStrings(WidgetActions.ARROW_FOLDED, TextOf(Child(menus.RecentRow, 1)));
    //the submenu opens to the right of its row
    try std.testing.expectEqual(@as(f32, 1), UIManager.GetUIComponent(menus.Recent, PopupComponent).?.mPlacement.Anchor.x);

    try std.testing.expect(!WidgetActions.IsChecked(menus.Grid));
    try WidgetActions.SetChecked(engine_context, menus.Grid, true);
    try std.testing.expect(WidgetActions.IsChecked(menus.Grid));
    try WidgetActions.SetChecked(engine_context, menus.Grid, false);
    try std.testing.expect(!WidgetActions.IsChecked(menus.Grid));
    //an item with no check box is never checked
    try WidgetActions.SetChecked(engine_context, menus.Save, true);
    try std.testing.expect(!WidgetActions.IsChecked(menus.Save));
}

test "moving onto a submenu row opens it, onto another row closes it, and picking an item closes every menu" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const menus = try Menus.Make(world);

    try WidgetActions.TogglePopup(engine_context, Child(menus.Bar, 0));
    try WidgetActions.OpenSubmenu(engine_context, menus.RecentRow);
    try std.testing.expect(world.IsOpen(menus.Recent));
    try std.testing.expectEqual(@as(usize, 2), world.OpenCount());
    //moving onto it again changes nothing
    try WidgetActions.OpenSubmenu(engine_context, menus.RecentRow);
    try std.testing.expectEqual(@as(usize, 2), world.OpenCount());

    try WidgetActions.HoverMenuItem(engine_context, menus.New);
    try std.testing.expect(!world.IsOpen(menus.Recent));
    try std.testing.expect(world.IsOpen(menus.File));

    try WidgetActions.OpenSubmenu(engine_context, menus.RecentRow);
    try WidgetActions.PickMenuItem(engine_context);
    try std.testing.expectEqual(@as(usize, 0), world.OpenCount());
}

test "moving along the menu bar switches menus only while one is open" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const menus = try Menus.Make(world);
    const file_button = Child(menus.Bar, 0);
    const edit_button = Child(menus.Bar, 1);

    try WidgetActions.HoverMenuBarButton(engine_context, edit_button);
    try std.testing.expectEqual(@as(usize, 0), world.OpenCount());

    try WidgetActions.TogglePopup(engine_context, file_button);
    try WidgetActions.OpenSubmenu(engine_context, menus.RecentRow);
    try WidgetActions.HoverMenuBarButton(engine_context, edit_button);
    try std.testing.expect(world.IsOpen(menus.Edit));
    try std.testing.expect(!world.IsOpen(menus.File));
    try std.testing.expect(!world.IsOpen(menus.Recent));

    try WidgetActions.HoverMenuBarButton(engine_context, file_button);
    try std.testing.expect(world.IsOpen(menus.File));
    try std.testing.expectEqual(@as(usize, 1), world.OpenCount());
}

test "a context menu is the target's popup, opened where it is right clicked" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const row = try Widgets.SelectableRow(engine_context, .{ .Entity = world.mPanel }, "Goblin", NO_SCRIPTS);
    const menu = try Widgets.ContextMenu(engine_context, row, NO_SCRIPTS);
    _ = try Widgets.MenuItem(engine_context, menu, "Delete", .{ .StockScripts = false });
    //the row keeps its style, and its element now names the menu
    try std.testing.expectEqualStrings("Header", StyleOf(row));
    try std.testing.expectEqual(menu.mID, WidgetActions.PopupOf(row).?.mID);
    try std.testing.expect(try WidgetActions.OpenContextMenu(engine_context, row));
    try std.testing.expect(world.IsOpen(menu));
    //a target with no menu opens nothing
    try std.testing.expect(!try WidgetActions.OpenContextMenu(engine_context, world.mPanel));
}

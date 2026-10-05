//! The editor shell's widgets (UI/Widgets.zig builders, UI/WidgetActions.zig behaviors) on real entities: splits whose
//! divider moves them, tab bars that show one page at a time, and floating windows that move, close and come to the
//! front. The stock scripts are only hooks; they are checked by compiling them, not here. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const UIManager = @import("../../UI/UIManager.zig");
const WidgetActions = @import("../../UI/WidgetActions.zig");
const Widgets = @import("../../UI/Widgets.zig");
const Layout = @import("../../UI/Layout.zig");

const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const SelectedTag = EntityComponents.SelectedTag;
const TextComponent = EntityComponents.TextComponent;
const TransformComponent = EntityComponents.TransformComponent;
const LayoutItemComponent = EntityComponents.LayoutItemComponent;
const StyleComponent = @import("../../ECSComponents/UIComponents.zig").StyleComponent;

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
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mUIManager.Deinit(engine_context);
        _ = engine_context._Internal.EngineGPA.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }
};

fn Item(entity: Entity) *LayoutItemComponent {
    return entity.GetComponent(LayoutItemComponent).?;
}

fn Depth(entity: Entity) f32 {
    return entity.GetComponent(TransformComponent).?.GetTranslation().z;
}

fn StyleOf(entity: Entity) []const u8 {
    return UIManager.GetUIComponent(entity, StyleComponent).?.mStyle.items;
}

fn Child(entity: Entity, index: usize) Entity {
    var children = entity.GetIterator(.Child);
    var child = children.next().?;
    for (0..index) |_| child = children.next().?;
    return child;
}

test "a split's divider moves it: the fixed pane grows and shrinks, and neither pane goes below the minimum" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    //a side panel 300 wide on the right, the rest of 1000 to the left
    const split = try Widgets.Split(engine_context, .{ .Entity = world.mPanel }, .Row, .Second, 300, NO_SCRIPTS);
    try std.testing.expectEqual(@as(f32, 1), Item(split.First).mWidth.Fill);
    try std.testing.expectEqualStrings("Divider", StyleOf(split.Divider));
    try std.testing.expectEqual(Widgets.DIVIDER_SIZE, Item(split.Divider).mWidth.Fixed);
    Item(split.First).mComputedSize = .{ .x = 696, .y = 500 };
    Item(split.Second).mComputedSize = .{ .x = 300, .y = 500 };

    //dragged left: the right pane takes it
    try WidgetActions.DragDivider(engine_context, split.Divider, .{ .x = -50, .y = 0, .z = 0 });
    try std.testing.expectEqual(@as(f32, 350), Item(split.Second).mWidth.Fixed);

    //as far right or left as it goes
    try WidgetActions.DragDivider(engine_context, split.Divider, .{ .x = 5000, .y = 0, .z = 0 });
    try std.testing.expectEqual(WidgetActions.MIN_PANE_SIZE, Item(split.Second).mWidth.Fixed);
    try WidgetActions.DragDivider(engine_context, split.Divider, .{ .x = -5000, .y = 0, .z = 0 });
    try std.testing.expectEqual(996 - WidgetActions.MIN_PANE_SIZE, Item(split.Second).mWidth.Fixed);

    //a column runs down, which is -y: dragging down grows a fixed top pane
    const column = try Widgets.Split(engine_context, .{ .Entity = world.mPanel }, .Column, .First, 200, NO_SCRIPTS);
    try WidgetActions.DragDivider(engine_context, column.Divider, .{ .x = 0, .y = -30, .z = 0 });
    try std.testing.expectEqual(@as(f32, 230), Item(column.First).mHeight.Fixed);
}

test "a tab bar shows its first tab's page to start with, and selecting a tab shows only its page" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const tabs = try Widgets.Tabs(engine_context, .{ .Entity = world.mPanel });
    const scenes = try Widgets.AddTab(engine_context, tabs, "Scenes", NO_SCRIPTS);
    const entities = try Widgets.AddTab(engine_context, tabs, "Entities", NO_SCRIPTS);
    const players = try Widgets.AddTab(engine_context, tabs, "Players", NO_SCRIPTS);
    const bar = Child(tabs, 0);
    try std.testing.expectEqualStrings("TabBar", StyleOf(bar));
    try std.testing.expectEqualStrings("Tab", StyleOf(Child(bar, 1)));
    try std.testing.expectEqualStrings("Entities", Child(Child(bar, 1), 0).GetComponent(TextComponent).?.mText.items);

    try std.testing.expect(Child(bar, 0).HasComponent(SelectedTag));
    try std.testing.expect(!Item(scenes).mCollapsed);
    try std.testing.expect(Item(entities).mCollapsed);

    try WidgetActions.SelectTab(engine_context, Child(bar, 2));
    try std.testing.expect(Item(scenes).mCollapsed);
    try std.testing.expect(Item(entities).mCollapsed);
    try std.testing.expect(!Item(players).mCollapsed);
    try std.testing.expect(!Child(bar, 0).HasComponent(SelectedTag));
    try std.testing.expect(Child(bar, 2).HasComponent(SelectedTag));
    try std.testing.expectEqual(players.mID, WidgetActions.PageOf(Child(bar, 2)).?.mID);
}

test "a floating window moves by its title bar, closes and opens, and comes in front of the others when raised" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;

    const stats = try Widgets.FloatingWindow(engine_context, world.mScene, "Stats", .{ .x = 300, .y = 200 }, .{ .x = 0, .y = 0 }, NO_SCRIPTS);
    const buses = try Widgets.FloatingWindow(engine_context, world.mScene, "Audio Buses", .{ .x = 300, .y = 200 }, .{ .x = 50, .y = 50 }, NO_SCRIPTS);
    try std.testing.expectEqualStrings("Title", StyleOf(stats.TitleBar));
    try std.testing.expectEqualStrings("Stats", Child(stats.TitleBar, 0).GetComponent(TextComponent).?.mText.items);
    //each new one starts in front, and every popup goes in front of them all
    try std.testing.expect(Depth(buses.Window) > Depth(stats.Window));
    try std.testing.expect(Widgets.POPUP_DEPTH > Depth(buses.Window));

    //raised from anywhere in it, here its content: the other one keeps its place behind
    try WidgetActions.RaiseWindow(engine_context, stats.Content);
    try std.testing.expect(Depth(stats.Window) > Depth(buses.Window));
    try std.testing.expectEqual(WidgetActions.WINDOW_DEPTH, Depth(buses.Window));

    try WidgetActions.MoveWindow(engine_context, stats.TitleBar, .{ .x = 10, .y = -20, .z = 0 });
    const offset = Item(stats.Window).mPlacement.Anchored.Offset;
    try std.testing.expectEqual(@as(f32, 10), offset.x);
    try std.testing.expectEqual(@as(f32, -20), offset.y);

    //closed by its close button, the title bar's last child
    try WidgetActions.CloseWindow(engine_context, Child(stats.TitleBar, 1));
    try std.testing.expect(!WidgetActions.IsWindowOpen(stats.Window));
    try WidgetActions.RaiseWindow(engine_context, buses.Window);
    try WidgetActions.OpenWindow(engine_context, stats.Window);
    try std.testing.expect(WidgetActions.IsWindowOpen(stats.Window));
    try std.testing.expect(Depth(stats.Window) > Depth(buses.Window));
}

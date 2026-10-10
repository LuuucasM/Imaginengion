//! The editor's menu bar (Programs/EditorMenuBar.zig): which item does what, and the editor's state on its items: check
//! marks, greyed out items, and the list of players to follow. No window needed. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const Player = @import("../../ECSObjects/Player.zig");
const Widgets = @import("../../UI/Widgets.zig");
const WidgetActions = @import("../../UI/WidgetActions.zig");
const EditorMenuBar = @import("../../Programs/EditorMenuBar.zig");

const DisabledTag = @import("../../ECSComponents/EComponents.zig").DisabledTag;

const TestWorld = struct {
    mEngineContext: *EngineContext,
    mBar: Entity = .uninit,

    fn Init() !*TestWorld {
        const self = try std.heap.page_allocator.create(TestWorld);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext) };
        const engine_context = self.mEngineContext;
        engine_context.* = .{};
        try engine_context.mUIManager.Init(engine_context.EngineAllocator());
        try engine_context.mEditorWorld.Init(engine_context.EngineAllocator());
        const scene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
        const root = try scene.CreateEntity(engine_context, Entity.DefaultConfig);
        self.mBar = try Widgets.MenuBar(engine_context, .{ .Entity = root });
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

fn State(players: []const Player, following: ?Player) EditorMenuBar.State {
    var shown = std.EnumArray(EditorMenuBar.Panel, bool).initFill(true);
    shown.set(.Stats, false);
    return .{ .Shown = shown, .ProjectOpen = false, .SceneSelected = false, .EntitySelected = false, .CanPlayStop = true, .PlayPreview = false, .VSync = true, .Players = players, .Following = following };
}

test "each item has its action, and the editor's state shows as check marks and greyed out items" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    var menu_bar = try EditorMenuBar.Build(engine_context, world.mBar, .{ .StockScripts = false });
    defer menu_bar.Deinit(engine_context.EngineAllocator());

    try std.testing.expectEqual(EditorMenuBar.Action.SaveProject, menu_bar.ActionOf(menu_bar.mSaveProject).?);
    try std.testing.expectEqual(.Player, menu_bar.ActionOf(menu_bar.mEntryItems.get(.Player)).?.SetProjectEntry);
    try std.testing.expectEqual(EditorMenuBar.Panel.Stats, menu_bar.ActionOf(menu_bar.mPanelItems.get(.Stats)).?.TogglePanel);
    //a menu itself is no item
    try std.testing.expect(menu_bar.ActionOf(world.mBar) == null);

    try menu_bar.Update(engine_context, State(&.{}, null));
    try std.testing.expect(WidgetActions.IsChecked(menu_bar.mPanelItems.get(.Components)));
    try std.testing.expect(!WidgetActions.IsChecked(menu_bar.mPanelItems.get(.Stats)));
    try std.testing.expect(!WidgetActions.IsChecked(menu_bar.mPlayPreview));
    //no project to save
    try std.testing.expect(menu_bar.mSaveProject.HasComponent(DisabledTag));
    try std.testing.expect(menu_bar.mEntryItems.get(.Scene).HasComponent(DisabledTag));
    try std.testing.expect(!menu_bar.mPlayStop.HasComponent(DisabledTag));
}

test "the save scene items need a scene selected, the save entity items an entity" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    var menu_bar = try EditorMenuBar.Build(engine_context, world.mBar, .{ .StockScripts = false });
    defer menu_bar.Deinit(engine_context.EngineAllocator());

    try std.testing.expectEqual(EditorMenuBar.Action.SaveSceneAs, menu_bar.ActionOf(menu_bar.mSaveSceneItems[1]).?);
    try std.testing.expectEqual(EditorMenuBar.Action.SaveEntity, menu_bar.ActionOf(menu_bar.mSaveEntityItems[0]).?);

    //nothing selected: all greyed out
    var state = State(&.{}, null);
    try menu_bar.Update(engine_context, state);
    for (menu_bar.mSaveSceneItems ++ menu_bar.mSaveEntityItems) |item| try std.testing.expect(item.HasComponent(DisabledTag));

    state.SceneSelected = true;
    try menu_bar.Update(engine_context, state);
    for (menu_bar.mSaveSceneItems) |item| try std.testing.expect(!item.HasComponent(DisabledTag));
    for (menu_bar.mSaveEntityItems) |item| try std.testing.expect(item.HasComponent(DisabledTag));

    state.SceneSelected = false;
    state.EntitySelected = true;
    try menu_bar.Update(engine_context, state);
    for (menu_bar.mSaveSceneItems) |item| try std.testing.expect(item.HasComponent(DisabledTag));
    for (menu_bar.mSaveEntityItems) |item| try std.testing.expect(!item.HasComponent(DisabledTag));
}

test "the VSync item toggles vsync, and is checked while it is on" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    var menu_bar = try EditorMenuBar.Build(engine_context, world.mBar, .{ .StockScripts = false });
    defer menu_bar.Deinit(engine_context.EngineAllocator());

    try std.testing.expectEqual(EditorMenuBar.Action.ToggleVSync, menu_bar.ActionOf(menu_bar.mVSync).?);

    var state = State(&.{}, null);
    try menu_bar.Update(engine_context, state);
    try std.testing.expect(WidgetActions.IsChecked(menu_bar.mVSync));
    state.VSync = false;
    try menu_bar.Update(engine_context, state);
    try std.testing.expect(!WidgetActions.IsChecked(menu_bar.mVSync));
}

test "the players to follow are listed, checked when followed, and listed again when they change" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    var menu_bar = try EditorMenuBar.Build(engine_context, world.mBar, .{ .StockScripts = false });
    defer menu_bar.Deinit(engine_context.EngineAllocator());

    const alice = try engine_context.mEditorWorld.CreatePlayer(engine_context, Player.DefaultConfig);
    const bob = try engine_context.mEditorWorld.CreatePlayer(engine_context, Player.DefaultConfig);

    try menu_bar.Update(engine_context, State(&.{ alice, bob }, bob));
    try std.testing.expectEqual(@as(usize, 2), menu_bar.mPlayerItems.items.len);
    const bob_item = menu_bar.mPlayerItems.items[1].Item;
    try std.testing.expectEqual(bob.mID, menu_bar.ActionOf(bob_item).?.FollowPlayer.mID);
    try std.testing.expect(WidgetActions.IsChecked(bob_item));
    try std.testing.expect(!WidgetActions.IsChecked(menu_bar.mPlayerItems.items[0].Item));

    //the same players: the same items
    try menu_bar.Update(engine_context, State(&.{ alice, bob }, null));
    try std.testing.expectEqual(bob_item.mID, menu_bar.mPlayerItems.items[1].Item.mID);
    try std.testing.expect(!WidgetActions.IsChecked(bob_item));

    //one gone: listed again
    try menu_bar.Update(engine_context, State(&.{alice}, null));
    try std.testing.expectEqual(@as(usize, 1), menu_bar.mPlayerItems.items.len);
    try std.testing.expect(menu_bar.ActionOf(bob_item) == null);
}

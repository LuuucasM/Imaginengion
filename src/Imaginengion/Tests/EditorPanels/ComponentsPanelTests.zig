//! The Components panel in the editor's own UI (EditorPanels/ComponentsPanel.zig): the lines saying what is selected
//! and why there is nothing to list, a header per component for each kind of object, built again when the selection
//! or its components change, Add and Delete through the menus, and the rows it adds that need the object: a rigid
//! body's type, a scene's layer, an audio component's Preview and Stop, Edit Template only with a template, and a UI
//! element's components with Edit UI Element. No window or renderer needed. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const Player = @import("../../ECSObjects/Player.zig");
const UIManager = @import("../../UI/UIManager.zig");
const WidgetActions = @import("../../UI/WidgetActions.zig");
const ComponentsPanel = @import("../../EditorPanels/ComponentsPanel.zig");
const SelectedObject = @import("../../Programs/EditorProgram.zig").SelectedObject;

const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const TextComponent = EntityComponents.TextComponent;
const LayoutComponent = EntityComponents.LayoutComponent;
const LayoutItemComponent = EntityComponents.LayoutItemComponent;
const RigidBodyComponent = EntityComponents.RigidBodyComponent;
const DynamicBodyTag = EntityComponents.DynamicBodyTag;
const AudioComponent = EntityComponents.AudioComponent;
const UIElementComponent = EntityComponents.UIElementComponent;
const TmplRefComponent = EntityComponents.TmplRefComponent;
const UIComponents = @import("../../ECSComponents/UIComponents.zig");

const TestPanel = struct {
    mEngineContext: *EngineContext,
    mScene: Scene = undefined,
    mGameScene: Scene = undefined,
    mPanel: ComponentsPanel = .{},

    fn Init() !*TestPanel {
        const self = try std.heap.page_allocator.create(TestPanel);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext) };
        const engine_context = self.mEngineContext;
        engine_context.* = .{};
        engine_context._Internal.ThreadedIO = std.Io.Threaded.init(engine_context._Internal.EngineGPA.allocator(), .{
            .concurrent_limit = .nothing,
            .async_limit = .nothing,
        });
        try engine_context.mAssetManager.Init(engine_context);
        try engine_context.mUIManager.Init(engine_context.EngineAllocator());
        try engine_context.mEditorWorld.Init(engine_context.EngineAllocator());
        try engine_context.mGameWorld.Init(engine_context.EngineAllocator());
        //an audio component's bus list
        try engine_context.mAudioManager.InitMixer(engine_context);
        self.mScene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
        self.mGameScene = try engine_context.mGameWorld.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
        //the shell's tab page
        const page = try self.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
        _ = try page.AddComponent(engine_context, LayoutComponent{ .mDirection = .Column });
        self.mPanel = try ComponentsPanel.Build(engine_context, page, .{ .StockScripts = false });
        return self;
    }

    fn Deinit(self: *TestPanel) void {
        const engine_context = self.mEngineContext;
        const engine_allocator = engine_context.EngineAllocator();
        self.mPanel.Deinit(engine_allocator);
        engine_context.mGameWorld.Deinit(engine_context);
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mUIManager.Deinit(engine_context);
        engine_context.mAudioManager.DeinitMixer(engine_context);
        const asset_manager = &engine_context.mAssetManager;
        asset_manager.mECSManager.Deinit(engine_context);
        asset_manager.mUUIDToWorldID.deinit(engine_allocator);
        asset_manager.mEventManager.Deinit(engine_allocator);
        asset_manager.mCWDPath.deinit(engine_allocator);
        _ = engine_context._Internal.EngineGPA.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }

    fn Update(self: *TestPanel, selected: ?SelectedObject) !void {
        try self.mPanel.Update(self.mEngineContext, selected);
    }

    /// The list of headers the selected object was built with
    fn Root(self: *TestPanel) Entity {
        return switch (self.mPanel.mBuiltFor.?) {
            .entity => self.mPanel.mEntityList.mRoot.?,
            .scene_layer => self.mPanel.mSceneList.mRoot.?,
            .player => self.mPanel.mPlayerList.mRoot.?,
            .gamecontext => self.mPanel.mGameContextList.mRoot.?,
        };
    }

    /// The headers' names, in order
    fn Headers(self: *TestPanel, out: [][]const u8) usize {
        var count: usize = 0;
        var parts = self.Root().GetIterator(.Child);
        var is_header = true;
        while (parts.next()) |part| : (is_header = !is_header) {
            if (!is_header) continue;
            if (count < out.len) out[count] = UIManager.LabelOf(part).?.GetComponent(TextComponent).?.mText.items;
            count += 1;
        }
        return count;
    }

    fn Contains(self: *TestPanel, name: []const u8) bool {
        var names: [32][]const u8 = undefined;
        for (names[0..self.Headers(&names)]) |header| {
            if (std.mem.eql(u8, header, name)) return true;
        }
        return false;
    }

    /// The action of the first of the panel's buttons that does `tag`
    fn ButtonFor(self: *TestPanel, tag: std.meta.Tag(ComponentsPanel.Action)) ?Entity {
        for (self.mPanel.mButtons.items) |entry| {
            if (entry.Action == tag) return entry.Button;
        }
        return null;
    }
};

fn TextOf(line: Entity) []const u8 {
    return line.GetComponent(TextComponent).?.mText.items;
}

test "the lines say what is selected, and each kind of object gets a header per component" {
    const test_panel = try TestPanel.Init();
    defer test_panel.Deinit();
    const engine_context = test_panel.mEngineContext;
    const panel = &test_panel.mPanel;

    try test_panel.Update(null);
    try std.testing.expectEqualStrings("Select an object to see its components", TextOf(panel.mMessage));

    const entity = try test_panel.mGameScene.CreateEntity(engine_context, Entity.DefaultConfig);
    try entity.SetName(engine_context, "Hero");
    try test_panel.Update(.{ .entity = entity });
    try std.testing.expectEqualStrings("Hero", TextOf(panel.mTitle));
    try std.testing.expect(panel.mMessage.GetComponent(LayoutItemComponent).?.mCollapsed);
    try std.testing.expect(test_panel.Contains("TransformComponent"));
    try std.testing.expect(test_panel.Contains("NameComponent"));

    //a scene and a player, each with its own list
    try test_panel.Update(.{ .scene_layer = test_panel.mGameScene });
    try std.testing.expect(test_panel.Contains("SceneComponent"));
    try std.testing.expect(!test_panel.Contains("TransformComponent"));
    const player = try engine_context.mGameWorld.CreatePlayer(engine_context, Player.DefaultConfig);
    try test_panel.Update(.{ .player = player });
    try std.testing.expect(test_panel.mPanel.mBuiltFor.? == .player);
    try std.testing.expect(test_panel.Contains("NameComponent"));
}

test "Add and Delete through the menus, built again when the components change" {
    const test_panel = try TestPanel.Init();
    defer test_panel.Deinit();
    const engine_context = test_panel.mEngineContext;
    const panel = &test_panel.mPanel;
    const entity = try test_panel.mGameScene.CreateEntity(engine_context, Entity.DefaultConfig);
    try test_panel.Update(.{ .entity = entity });
    const root = test_panel.Root();

    //an Add item for the collider, from the panel's own menu
    var add_collider: ?ComponentsPanel.Action = null;
    const collider_index = comptime blk: {
        for (EntityComponents.ComponentPanelList, 0..) |component_type, i| {
            if (component_type == EntityComponents.ColliderComponent) break :blk i;
        }
        unreachable;
    };
    for (panel.mEntityList.mItems.items) |entry| {
        if (entry.Action == .Add and entry.Action.Add == collider_index) add_collider = panel.ActionOf(entry.Item);
    }
    try panel.Run(engine_context, add_collider.?);
    try std.testing.expect(entity.HasComponent(EntityComponents.ColliderComponent));
    try test_panel.Update(.{ .entity = entity });
    try std.testing.expect(test_panel.Root().mID != root.mID);
    try std.testing.expect(test_panel.Contains("ColliderComponent"));

    //its header's Delete
    var delete_collider: ?ComponentsPanel.Action = null;
    for (panel.mEntityList.mItems.items) |entry| {
        if (entry.Action == .Delete and entry.Action.Delete == collider_index) delete_collider = panel.ActionOf(entry.Item);
    }
    try std.testing.expect(delete_collider != null);
}

test "a rigid body's type is picked under it, a scene shows its layer, and audio has Preview and Stop" {
    const test_panel = try TestPanel.Init();
    defer test_panel.Deinit();
    const engine_context = test_panel.mEngineContext;
    const panel = &test_panel.mPanel;
    const entity = try test_panel.mGameScene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try entity.AddComponent(engine_context, RigidBodyComponent{});
    _ = try entity.AddComponent(engine_context, AudioComponent{});
    try test_panel.Update(.{ .entity = entity });

    const dropdown = panel.mBodyType.?;
    const dynamic_index = comptime blk: {
        for (Entity.BodyTypeTags, 0..) |tag_type, i| {
            if (tag_type == DynamicBodyTag) break :blk i;
        }
        unreachable;
    };
    try WidgetActions.TogglePopup(engine_context, dropdown);
    var choices = WidgetActions.PopupOf(dropdown).?.GetIterator(.Child);
    var choice = choices.next().?;
    for (0..dynamic_index) |_| choice = choices.next().?;
    try WidgetActions.Choose(engine_context, choice);
    try engine_context.mUIManager.ProcessUIEvents(engine_context, .{});
    //the editor hands the panel the frame's UI events
    try panel.OnUIEvent(engine_context, .{ .ValueChanged = .{ .mEntity = dropdown, .mTarget = dropdown } });
    try std.testing.expect(entity.HasComponent(DynamicBodyTag));

    try std.testing.expect(test_panel.ButtonFor(.Preview) != null);
    try std.testing.expectEqual(ComponentsPanel.Action.Stop, panel.ActionOf(test_panel.ButtonFor(.Stop).?).?);
    //no template, no Edit Template
    try std.testing.expect(test_panel.ButtonFor(.EditTemplate) == null);

    try test_panel.Update(.{ .scene_layer = test_panel.mGameScene });
    var found_layer = false;
    var parts = test_panel.Root().GetIterator(.Child);
    while (parts.next()) |part| {
        var rows = part.GetIterator(.Child);
        while (rows.next()) |row| {
            if (row.GetComponent(TextComponent)) |text| {
                if (std.mem.eql(u8, text.mText.items, "Layer: GameLayer")) found_layer = true;
            }
        }
    }
    try std.testing.expect(found_layer);
}

test "a UI element's components are listed under it, with Edit UI Element" {
    const test_panel = try TestPanel.Init();
    defer test_panel.Deinit();
    const engine_context = test_panel.mEngineContext;
    const panel = &test_panel.mPanel;
    const entity = try test_panel.mGameScene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try entity.AddComponent(engine_context, UIElementComponent{});
    _ = try UIManager.ElementOf(entity).?.AddComponent(engine_context, UIComponents.ScrollComponent{});
    try test_panel.Update(.{ .entity = entity });

    try std.testing.expectEqual(ComponentsPanel.Action.EditUIElement, panel.ActionOf(test_panel.ButtonFor(.EditUIElement).?).?);
    var found = false;
    var parts = test_panel.Root().GetIterator(.Child);
    while (parts.next()) |part| {
        var rows = part.GetIterator(.Child);
        while (rows.next()) |row| {
            if (row.GetComponent(TextComponent)) |text| {
                if (std.mem.eql(u8, text.mText.items, "ScrollComponent")) found = true;
            }
        }
    }
    try std.testing.expect(found);
}

test "building again takes away the popups the old rows opened, a dropdown's list and a field's Clear menu" {
    const test_panel = try TestPanel.Init();
    defer test_panel.Deinit();
    const engine_context = test_panel.mEngineContext;
    const panel = &test_panel.mPanel;
    const body = try test_panel.mGameScene.CreateEntity(engine_context, Entity.DefaultConfig);
    _ = try body.AddComponent(engine_context, RigidBodyComponent{});
    try test_panel.Update(.{ .entity = body });
    //they live at the top of the scene, outside the rows
    const list = WidgetActions.PopupOf(panel.mBodyType.?).?;
    try std.testing.expect(list.IsActive());

    const other = try test_panel.mGameScene.CreateEntity(engine_context, Entity.DefaultConfig);
    try test_panel.Update(.{ .entity = other });
    //deleted at the end of the frame, with the rows
    var callback_list: std.DoublyLinkedList = .{};
    try engine_context.mEditorWorld.ProcessEvents(@import("../../Events/EManagerData.zig"), .EndOfFrame, engine_context, &callback_list);
    try engine_context.mEditorWorld.ProcessEvents(@import("../../Events/ECSEventData.zig"), .EndOfFrame, engine_context, &callback_list);
    try std.testing.expect(!list.IsActive());
}


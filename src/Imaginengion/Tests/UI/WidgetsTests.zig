//! The stock widget behaviors (UI/WidgetActions.zig, which the stock scripts call) and the widget builders
//! (UI/Widgets.zig), on real entities. The stock scripts themselves are only hooks; they are checked by compiling them,
//! not here. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const UIEvent = @import("../../Events/UIEventData.zig").EventT;
const UIManager = @import("../../UI/UIManager.zig");
const WidgetActions = @import("../../UI/WidgetActions.zig");
const Widgets = @import("../../UI/Widgets.zig");
const Layout = @import("../../UI/Layout.zig");

const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const SelectedTag = EntityComponents.SelectedTag;
const QuadComponent = EntityComponents.QuadComponent;
const TextComponent = EntityComponents.TextComponent;
const LayoutComponent = EntityComponents.LayoutComponent;
const LayoutItemComponent = EntityComponents.LayoutItemComponent;
const UIElementComponent = EntityComponents.UIElementComponent;
const UIComponents = @import("../../ECSComponents/UIComponents.zig");
const PopupComponent = UIComponents.PopupComponent;
const PopupRefComponent = UIComponents.PopupRefComponent;
const StyleComponent = UIComponents.StyleComponent;

const TestWorld = struct {
    mEngineContext: *EngineContext,
    mScene: Scene = undefined,
    mList: Entity = .uninit,

    fn Init() !*TestWorld {
        const self = try std.heap.page_allocator.create(TestWorld);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext) };
        const engine_context = self.mEngineContext;
        engine_context.* = .{};
        try engine_context.mUIManager.Init(engine_context.EngineAllocator());
        try engine_context.mEditorWorld.Init(engine_context.EngineAllocator());
        try engine_context.mSimulateWorld.Init(engine_context.EngineAllocator());
        self.mScene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
        self.mList = try self.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
        return self;
    }

    fn Deinit(self: *TestWorld) void {
        const engine_context = self.mEngineContext;
        engine_context.mPointerSystem.Deinit(engine_context.EngineAllocator());
        engine_context.mSimulateWorld.Deinit(engine_context);
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mUIManager.Deinit(engine_context);
        _ = engine_context._Internal.EngineGPA.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }

    fn Child(self: *TestWorld) !Entity {
        return try self.mList.CreateChild(self.mEngineContext, .Entity, Entity.DefaultConfig);
    }

    /// The ValueChanged events sent since the last call: who each went to
    fn TakeValueChanged(self: *TestWorld) ![]Entity {
        const queued = self.mEngineContext.mUIManager.mEventManager.mEventsArray.getPtr(.UI);
        var to: std.ArrayList(Entity) = .empty;
        for (queued.items) |event| {
            switch (event) {
                .ValueChanged => |e| try to.append(self.mEngineContext.FrameAllocator(), e.mEntity),
                else => {},
            }
        }
        queued.clearRetainingCapacity();
        return to.items;
    }

    /// A popup root, and an opener whose UI element names it
    fn PopupAndOpener(self: *TestWorld) !struct { Popup: Entity, Opener: Entity } {
        const engine_context = self.mEngineContext;
        const popup = try self.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
        _ = try popup.AddComponent(engine_context, UIElementComponent{});
        _ = try UIManager.ElementOf(popup).?.AddComponent(engine_context, PopupComponent{});
        _ = try popup.AddComponent(engine_context, LayoutItemComponent{});
        const opener = try self.Child();
        _ = try opener.AddComponent(engine_context, UIElementComponent{});
        _ = try UIManager.ElementOf(opener).?.AddComponent(engine_context, PopupRefComponent{ .mPopup = popup });
        return .{ .Popup = popup, .Opener = opener };
    }
};

fn ExpectTo(expected: []const Entity, actual: []const Entity) !void {
    try std.testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |e, a| try std.testing.expectEqual(e.mID, a.mID);
}

test "toggling checks and unchecks, and tells it and everything it is inside" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const box = try world.Child();

    try WidgetActions.Toggle(engine_context, box);
    try std.testing.expect(box.HasComponent(SelectedTag));
    try ExpectTo(&.{ box, world.mList }, try world.TakeValueChanged());

    try WidgetActions.Toggle(engine_context, box);
    try std.testing.expect(!box.HasComponent(SelectedTag));
    try ExpectTo(&.{ box, world.mList }, try world.TakeValueChanged());
}

test "selecting one row unselects its siblings, and selecting the selected one again changes nothing" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const a = try world.Child();
    const b = try world.Child();
    const c = try world.Child();

    try WidgetActions.Select(engine_context, a);
    _ = try world.TakeValueChanged();
    try WidgetActions.Select(engine_context, c);
    try std.testing.expect(!a.HasComponent(SelectedTag));
    try std.testing.expect(!b.HasComponent(SelectedTag));
    try std.testing.expect(c.HasComponent(SelectedTag));
    try ExpectTo(&.{ c, world.mList }, try world.TakeValueChanged());

    try WidgetActions.Select(engine_context, c);
    try std.testing.expectEqual(@as(usize, 0), (try world.TakeValueChanged()).len);
}

test "an opener opens the popup it names against itself and closes it again, and a menu item closes them all" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const popups = &engine_context.mUIManager.mPopupSystem;
    const pair = try world.PopupAndOpener();

    try WidgetActions.TogglePopup(engine_context, pair.Opener);
    try std.testing.expect(popups.IsOpen(pair.Popup));
    try std.testing.expectEqual(pair.Opener.mID, popups.OpenPopups()[0].mAt.Opener.mID);
    try WidgetActions.TogglePopup(engine_context, pair.Opener);
    try std.testing.expect(!popups.IsOpen(pair.Popup));

    //with nowhere for the pointer to be, a right-click menu opens against what was right clicked
    try WidgetActions.OpenContextMenu(engine_context, pair.Opener);
    try std.testing.expect(popups.IsOpen(pair.Popup));
    try WidgetActions.ClosePopups(engine_context);
    try std.testing.expect(!popups.IsOpen(pair.Popup));

    //nothing named: nothing happens
    const plain = try world.Child();
    try WidgetActions.TogglePopup(engine_context, plain);
    try std.testing.expectEqual(@as(usize, 0), popups.OpenPopups().len);
}

test "a header folds away the entity right after it, and the last one folds nothing" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const header = try world.Child();
    const content = try world.Child();

    try WidgetActions.CollapseNext(engine_context, header);
    try std.testing.expect(content.GetComponent(LayoutItemComponent).?.mCollapsed);
    try WidgetActions.CollapseNext(engine_context, header);
    try std.testing.expect(!content.GetComponent(LayoutItemComponent).?.mCollapsed);

    //content is the last child: the list's first child (the header) is not after it
    try WidgetActions.CollapseNext(engine_context, content);
    try std.testing.expect(!header.HasComponent(LayoutItemComponent));
}

fn StyleOf(entity: Entity) []const u8 {
    return UIManager.GetUIComponent(entity, StyleComponent).?.mStyle.items;
}

fn FirstChild(entity: Entity) Entity {
    var children = entity.GetIterator(.Child);
    return children.next().?;
}

test "the builders make each widget out of quads, text, layout and styles" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const list: Widgets.Parent = .{ .Entity = world.mList };
    const no_scripts = Widgets.Options{ .StockScripts = false };

    const button = try Widgets.Button(engine_context, list, "Play");
    try std.testing.expect(button.HasComponent(QuadComponent));
    try std.testing.expectEqual(Layout.Direction.Row, button.GetComponent(LayoutComponent).?.mDirection);
    try std.testing.expectEqualStrings("Button", StyleOf(button));
    const label = FirstChild(button);
    try std.testing.expectEqualStrings("Play", label.GetComponent(TextComponent).?.mText.items);
    try std.testing.expectEqualStrings("Text", StyleOf(label));

    const checkbox = try Widgets.Checkbox(engine_context, list, "Fullscreen", no_scripts);
    const box = FirstChild(checkbox);
    try std.testing.expectEqualStrings("Checkbox", StyleOf(box));
    try std.testing.expectEqual(Widgets.CHECKBOX_SIZE, box.GetComponent(LayoutItemComponent).?.mWidth.Fixed);

    const row = try Widgets.SelectableRow(engine_context, list, "Goblin", no_scripts);
    try std.testing.expectEqualStrings("Header", StyleOf(row));
    try std.testing.expectEqual(@as(f32, 1), row.GetComponent(LayoutItemComponent).?.mWidth.Fill);

    const separator = try Widgets.Separator(engine_context, list);
    try std.testing.expectEqualStrings("Separator", StyleOf(separator));
    try std.testing.expectEqual(@as(f32, 1), separator.GetComponent(LayoutItemComponent).?.mHeight.Fixed);

    //and at the top of a scene
    const top = try Widgets.Label(engine_context, .{ .Scene = world.mScene }, "Title");
    try std.testing.expect(!top.HasComponent(@import("../../ECS/Components.zig").ChildComponent(Entity.Type)));
}

test "an opener in a copied world opens the copied world's popup" {
    const world = try TestWorld.Init();
    defer world.Deinit();
    const engine_context = world.mEngineContext;
    const pair = try world.PopupAndOpener();

    try engine_context.mEditorWorld.Copy(engine_context, &engine_context.mSimulateWorld);
    const opener_copy = engine_context.mSimulateWorld.GetEntity(pair.Opener.mID);
    const popup = WidgetActions.PopupOf(opener_copy).?;
    try std.testing.expectEqual(pair.Popup.mID, popup.mID);
    try std.testing.expectEqual(@as(*@import("../../Core/WorldManager.zig"), &engine_context.mSimulateWorld), popup.mManager);
    //the original still opens its own
    try std.testing.expectEqual(&engine_context.mEditorWorld, WidgetActions.PopupOf(pair.Opener).?.mManager);
}

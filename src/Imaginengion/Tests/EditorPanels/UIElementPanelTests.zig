//! The UI Element panel in the editor's own UI (EditorPanels/UIElementPanel.zig) and the component list it is built
//! from (EditorPanels/ComponentList.zig): the line saying why there is nothing to list, a header per component with the
//! rows its UIRender asks for, the add and delete menus, building again when the selection or components change, and
//! the UI components' own rows (optional limits, the popup presets, an entity's name, a scroll edit laying the entity
//! out again). Edits are made the way the widgets make them. No window needed. Run with `zig build test-engine`.
const std = @import("std");

const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const UIElement = @import("../../ECSObjects/UIElement.zig");
const UIManager = @import("../../UI/UIManager.zig");
const WidgetActions = @import("../../UI/WidgetActions.zig");
const UIElementPanel = @import("../../EditorPanels/UIElementPanel.zig");
const SelectedObject = @import("../../Programs/EditorProgram.zig").SelectedObject;

const EntityComponents = @import("../../ECSComponents/EComponents.zig");
const TextComponent = EntityComponents.TextComponent;
const AttribComponent = EntityComponents.AttribComponent;
const LayoutItemComponent = EntityComponents.LayoutItemComponent;
const MaskComponent = EntityComponents.MaskComponent;
const ShapeComponent = EntityComponents.ShapeComponent;
const UIElementComponent = EntityComponents.UIElementComponent;
const SelectedTag = EntityComponents.SelectedTag;
const DisabledTag = EntityComponents.DisabledTag;
const LayoutDirtyTag = EntityComponents.LayoutDirtyTag;
const UIComponents = @import("../../ECSComponents/UIComponents.zig");

const Components = UIElementPanel.Components;

const TestPanel = struct {
    mEngineContext: *EngineContext,
    mScene: Scene = undefined,
    mPanel: UIElementPanel = .{},

    fn Init() !*TestPanel {
        const self = try std.heap.page_allocator.create(TestPanel);
        self.* = .{ .mEngineContext = try std.heap.page_allocator.create(EngineContext) };
        const engine_context = self.mEngineContext;
        engine_context.* = .{};
        try engine_context.mUIManager.Init(engine_context.EngineAllocator());
        try engine_context.mEditorWorld.Init(engine_context.EngineAllocator());
        self.mScene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer, Scene.DefaultConfig);
        self.mPanel = try UIElementPanel.Build(engine_context, self.mScene, .{ .StockScripts = false });
        try self.mPanel.Toggle(engine_context);
        return self;
    }

    fn Deinit(self: *TestPanel) void {
        const engine_context = self.mEngineContext;
        self.mPanel.Deinit(engine_context.EngineAllocator());
        engine_context.mEditorWorld.Deinit(engine_context);
        engine_context.mUIManager.Deinit(engine_context);
        _ = engine_context._Internal.EngineGPA.deinit();
        std.heap.page_allocator.destroy(engine_context);
        std.heap.page_allocator.destroy(self);
    }

    /// An entity with a UI element, and the element
    fn ElementEntity(self: *TestPanel) !struct { Entity, UIElement } {
        const entity = try self.mScene.CreateEntity(self.mEngineContext, Entity.DefaultConfig);
        _ = try entity.AddComponent(self.mEngineContext, UIElementComponent{});
        return .{ entity, UIManager.ElementOf(entity).? };
    }

    fn Update(self: *TestPanel, entity: Entity) !void {
        try self.mPanel.Update(self.mEngineContext, SelectedObject{ .entity = entity });
    }

    fn Message(self: *TestPanel) []const u8 {
        return self.mPanel.mMessage.GetComponent(TextComponent).?.mText.items;
    }

    /// The rows under the `index`th component's header
    fn Rows(self: *TestPanel, index: usize, out: []Entity) usize {
        //the list is header, content, header, content...
        var parts: [32]Entity = undefined;
        _ = Children(self.mPanel.mList.mRoot.?, &parts);
        return Children(parts[index * 2 + 1], out);
    }

    /// The edit the widgets make: the frame's UI events handed out
    fn ProcessUIEvents(self: *TestPanel) !void {
        try self.mEngineContext.mUIManager.ProcessUIEvents(self.mEngineContext, .{});
    }
};

fn Children(entity: Entity, out: []Entity) usize {
    var count: usize = 0;
    var children = entity.GetIterator(.Child);
    while (children.next()) |child| : (count += 1) {
        if (count < out.len) out[count] = child;
    }
    return count;
}

/// What comes after a row's label
fn Part(row: Entity, index: usize) Entity {
    var parts: [4]Entity = undefined;
    _ = Children(row, &parts);
    return parts[index];
}

fn IndexOf(comptime component_type: type) usize {
    return comptime blk: {
        for (UIComponents.ComponentsPanelList, 0..) |listed, i| {
            if (listed == component_type) break :blk i;
        }
        unreachable;
    };
}

test "the line says why there is nothing to list, and folds away when there is" {
    const test_panel = try TestPanel.Init();
    defer test_panel.Deinit();
    const engine_context = test_panel.mEngineContext;
    const panel = &test_panel.mPanel;

    try panel.Update(engine_context, null);
    try std.testing.expectEqualStrings("Select an entity to see its UI element", test_panel.Message());
    try panel.Update(engine_context, .{ .scene_layer = test_panel.mScene });
    try std.testing.expectEqualStrings("Only an entity can have a UI element", test_panel.Message());
    const plain = try test_panel.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
    try test_panel.Update(plain);
    try std.testing.expect(std.mem.startsWith(u8, test_panel.Message(), "This entity has no UI element"));
    try std.testing.expect(panel.mList.mRoot == null);

    const entity, const element = try test_panel.ElementEntity();
    try test_panel.Update(entity);
    try std.testing.expectEqualStrings("No UI components yet. Right click to add one", test_panel.Message());
    try std.testing.expect(!panel.mMessage.GetComponent(LayoutItemComponent).?.mCollapsed);

    _ = try element.AddComponent(engine_context, UIComponents.StyleComponent{});
    try test_panel.Update(entity);
    try std.testing.expectEqualStrings("", test_panel.Message());
    try std.testing.expect(panel.mMessage.GetComponent(LayoutItemComponent).?.mCollapsed);
}

test "a header per component, rows from UIRender, and the add and delete menus" {
    const test_panel = try TestPanel.Init();
    defer test_panel.Deinit();
    const engine_context = test_panel.mEngineContext;
    const panel = &test_panel.mPanel;
    const entity, const element = try test_panel.ElementEntity();
    _ = try element.AddComponent(engine_context, UIComponents.StyleComponent{});
    _ = try element.AddComponent(engine_context, UIComponents.SelectionGroupComponent{});
    try test_panel.Update(entity);

    //a header and its content each, in the list's order: style, then selection group
    var parts: [16]Entity = undefined;
    try std.testing.expectEqual(@as(usize, 4), Children(panel.mList.mRoot.?, &parts));
    var rows: [8]Entity = undefined;
    try std.testing.expectEqual(@as(usize, 1), test_panel.Rows(0, &rows));
    //no UIRender: an empty header, still there to delete
    try std.testing.expectEqual(@as(usize, 0), test_panel.Rows(1, &rows));

    //a delete for each, and an add for each of the six it hasn't
    try std.testing.expectEqual(@as(usize, 2 + 6), panel.mList.mItems.items.len);
    try std.testing.expectEqual(IndexOf(UIComponents.StyleComponent), panel.ActionOf(panel.mList.mItems.items[0].Item).?.Delete);
    var adds_scroll = false;
    for (panel.mList.mItems.items) |entry| {
        if (entry.Action == .Add and entry.Action.Add == IndexOf(UIComponents.ScrollComponent)) adds_scroll = true;
        if (entry.Action == .Add) try std.testing.expect(entry.Action.Add != IndexOf(UIComponents.StyleComponent));
    }
    try std.testing.expect(adds_scroll);

    //adding a scroll the way the menu does gives the entity the mask it needs and a shape to mask with, and the list is
    //built again with it
    const old_root = panel.mList.mRoot.?;
    try panel.Run(engine_context, .{ .Add = IndexOf(UIComponents.ScrollComponent) });
    try std.testing.expect(element.HasComponent(UIComponents.ScrollComponent));
    try std.testing.expect(entity.HasComponent(MaskComponent));
    try std.testing.expect(entity.HasComponent(ShapeComponent));
    try test_panel.Update(entity);
    try std.testing.expect(panel.mList.mRoot.?.mID != old_root.mID);
    try std.testing.expect(old_root.GetComponent(LayoutItemComponent).?.mCollapsed);
    try std.testing.expectEqual(@as(usize, 6), Children(panel.mList.mRoot.?, &parts));

    //nothing changed: not built again
    const root = panel.mList.mRoot.?;
    try test_panel.Update(entity);
    try std.testing.expectEqual(root.mID, panel.mList.mRoot.?.mID);

    //a component taken away, and another entity selected, each build it again
    try element.RemoveComponentSync(engine_context, UIComponents.SelectionGroupComponent);
    try test_panel.Update(entity);
    try std.testing.expect(panel.mList.mRoot.?.mID != root.mID);
    const other, _ = try test_panel.ElementEntity();
    try test_panel.Update(other);
    try std.testing.expectEqual(@as(usize, 0), Children(panel.mList.mRoot.?, &parts));
}

test "a limit is ticked on with the number usable, its decimals a byte, and its edits written" {
    const test_panel = try TestPanel.Init();
    defer test_panel.Deinit();
    const engine_context = test_panel.mEngineContext;
    const entity, const element = try test_panel.ElementEntity();
    _ = try element.AddComponent(engine_context, UIComponents.NumberFieldComponent{});
    try test_panel.Update(entity);

    //Speed, Min, Max, Decimals. Min is its label, the checkbox, and the number, greyed out with no limit
    var rows: [8]Entity = undefined;
    try std.testing.expectEqual(@as(usize, 4), test_panel.Rows(0, &rows));
    try std.testing.expect(Part(rows[1], 2).HasComponent(DisabledTag));

    const box = Part(Part(rows[1], 1), 0);
    _ = try box.AddComponent(engine_context, SelectedTag{});
    try engine_context.mUIManager.SendToChain(engine_context, box, .ValueChanged);
    try test_panel.ProcessUIEvents();
    try std.testing.expectEqual(@as(?f32, 0), element.GetComponent(UIComponents.NumberFieldComponent).?.mMin);

    //built again for it: the number is usable now, and its edits are the limit
    try test_panel.Update(entity);
    try std.testing.expectEqual(@as(usize, 4), test_panel.Rows(0, &rows));
    const min = Part(rows[1], 2);
    try std.testing.expect(!min.HasComponent(DisabledTag));
    min.GetComponent(AttribComponent).?.mData.SetFromFloat(-5);
    try engine_context.mUIManager.SendToChain(engine_context, min, .ValueChanged);
    try test_panel.ProcessUIEvents();
    try std.testing.expectEqual(@as(?f32, -5), element.GetComponent(UIComponents.NumberFieldComponent).?.mMin);

    const decimals = Part(rows[3], 1);
    decimals.GetComponent(AttribComponent).?.mData.SetFromFloat(300);
    try engine_context.mUIManager.SendToChain(engine_context, decimals, .ValueChanged);
    try test_panel.ProcessUIEvents();
    try std.testing.expectEqual(@as(u8, 255), element.GetComponent(UIComponents.NumberFieldComponent).?.mDecimals);
}

test "the popup's placement shows as a preset, Custom when none, and picking one sets the anchor and pivot" {
    const test_panel = try TestPanel.Init();
    defer test_panel.Deinit();
    const engine_context = test_panel.mEngineContext;
    const entity, const element = try test_panel.ElementEntity();
    _ = try element.AddComponent(engine_context, UIComponents.PopupComponent{});
    try test_panel.Update(entity);

    var rows: [8]Entity = undefined;
    try std.testing.expectEqual(@as(usize, 4), test_panel.Rows(0, &rows));
    const dropdown = Part(rows[0], 1);
    try std.testing.expectEqualStrings("Below", UIManager.LabelOf(dropdown).?.GetComponent(TextComponent).?.mText.items);

    //moved off every preset by code: shown as Custom
    element.GetComponent(UIComponents.PopupComponent).?.mPlacement.Anchor.x = 0.5;
    try engine_context.mUIManager.mBindingSystem.Update(engine_context);
    try std.testing.expectEqualStrings("Custom", UIManager.LabelOf(dropdown).?.GetComponent(TextComponent).?.mText.items);

    //Right, picked from the list
    try WidgetActions.TogglePopup(engine_context, dropdown);
    var choices = WidgetActions.PopupOf(dropdown).?.GetIterator(.Child);
    _ = choices.next().?;
    try WidgetActions.Choose(engine_context, choices.next().?);
    try test_panel.ProcessUIEvents();
    const placement = element.GetComponent(UIComponents.PopupComponent).?.mPlacement;
    try std.testing.expect(placement.Anchor.x == 1 and placement.Anchor.y == 1 and placement.Pivot.x == -1 and placement.Pivot.y == 1);
}

test "a popup ref shows its popup's name, and a scroll edit lays the entity out again" {
    const test_panel = try TestPanel.Init();
    defer test_panel.Deinit();
    const engine_context = test_panel.mEngineContext;
    const entity, const element = try test_panel.ElementEntity();
    const menu = try test_panel.mScene.CreateEntity(engine_context, Entity.DefaultConfig);
    try menu.SetName(engine_context, "Menu");
    _ = try element.AddComponent(engine_context, UIComponents.ScrollComponent{});
    _ = try element.AddComponent(engine_context, UIComponents.PopupRefComponent{ .mPopup = menu });
    try test_panel.Update(entity);

    //the list's order: scroll, then the popup ref
    var rows: [8]Entity = undefined;
    _ = test_panel.Rows(1, &rows);
    const name = Part(rows[0], 1);
    try std.testing.expectEqualStrings("Menu", name.GetComponent(TextComponent).?.mText.items);
    element.GetComponent(UIComponents.PopupRefComponent).?.mPopup = .uninit;
    try engine_context.mUIManager.mBindingSystem.Update(engine_context);
    try std.testing.expectEqualStrings("None", name.GetComponent(TextComponent).?.mText.items);

    try entity.ClearLayoutDirty(engine_context);
    _ = test_panel.Rows(0, &rows);
    const wheel_step = Part(rows[1], 1);
    wheel_step.GetComponent(AttribComponent).?.mData.SetFromFloat(20);
    try engine_context.mUIManager.SendToChain(engine_context, wheel_step, .ValueChanged);
    try test_panel.ProcessUIEvents();
    try std.testing.expectEqual(@as(f32, 20), element.GetComponent(UIComponents.ScrollComponent).?.mWheelStep);
    try std.testing.expect(entity.HasComponent(LayoutDirtyTag));
}

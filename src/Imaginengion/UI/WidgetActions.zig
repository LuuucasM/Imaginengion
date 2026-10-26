//! What the stock widget scripts do (EngineAssets/scripts/UI/), as engine functions: the behaviors nearly every game's
//! UI needs, built only from the primitives (tags, popups, layout). A widget isn't anything to the engine: an entity is
//! a checkbox because its script toggles it when it is clicked. The stock scripts are only the hook that calls these,
//! so a game's own scripts can call them too, and they are tested without compiling a script.
const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const UIManager = @import("UIManager.zig");
const PopupSystem = @import("PopupSystem.zig");

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const SelectedTag = EntityComponents.SelectedTag;
const LayoutItemComponent = EntityComponents.LayoutItemComponent;
const TextComponent = EntityComponents.TextComponent;
const ShapeComponent = EntityComponents.ShapeComponent;
const SurfaceComponent = EntityComponents.SurfaceComponent;
const AttribComponent = EntityComponents.AttribComponent;
const Vec4 = @import("../Math/MathTypes.zig").Vec4;
const UIComponents = @import("../ECSComponents/UIComponents.zig");
const PopupRefComponent = UIComponents.PopupRefComponent;
const PopupComponent = UIComponents.PopupComponent;
const SelectionGroupComponent = UIComponents.SelectionGroupComponent;
const FloatingWindowComponent = UIComponents.FloatingWindowComponent;
const LayoutComponent = EntityComponents.LayoutComponent;
const TransformComponent = EntityComponents.TransformComponent;
const EntitySceneComponent = EntityComponents.EntitySceneComponent;
const UIElement = @import("../ECSObjects/UIElement.zig");
const Vec3 = @import("../Math/MathTypes.zig").Vec3;
const NumberFieldSystem = @import("NumberFieldSystem.zig");
const ECSComponents = @import("../ECS/Components.zig");
const EntityChildComponent = ECSComponents.ChildComponent(Entity.Type);

//a widget's value goes in an AttribComponent, set through NumberFieldSystem.SetValue so it keeps a number field's limits
//and sends ValueChanged
pub const SetValue = NumberFieldSystem.SetValue;

/// Checked or unchecked: adds `SelectedTag` to the entity, or takes it off, and shows `mark` (a check mark,
/// Widgets.AddCheckMark) only while it is checked. uninit for no mark. ValueChanged goes to it and its parents
pub fn Toggle(engine_context: *EngineContext, entity: Entity, mark: Entity) !void {
    const checked = !entity.HasComponent(SelectedTag);
    if (checked) {
        _ = try entity.AddComponent(engine_context, SelectedTag{});
    } else {
        //at once, so it is drawn unchecked this frame
        try entity.RemoveComponentSync(engine_context, SelectedTag);
    }
    if (mark.IsActive()) {
        if (mark.GetComponentMut(LayoutItemComponent)) |item| {
            item.mCollapsed = !checked;
            try mark.MarkLayoutDirty(engine_context);
        }
    }
    try engine_context.mUIManager.SendToChain(engine_context, entity, .ValueChanged);
}

/// The one picked out of its group, like a row of a list or a tree: `SelectedTag` on the entity, and off every other
/// entity in the tree of the nearest selection group it is inside (SelectionGroupComponent), or off its siblings if it
/// is in none. ValueChanged goes to it and its parents, unless it was already the selected one
pub fn Select(engine_context: *EngineContext, entity: Entity) !void {
    if (entity.HasComponent(SelectedTag)) return;
    if (GroupOf(entity)) |group| {
        try UnselectTree(engine_context, group);
        _ = try entity.AddComponent(engine_context, SelectedTag{});
    } else {
        _ = try SelectAmongSiblings(engine_context, entity);
    }
    try engine_context.mUIManager.SendToChain(engine_context, entity, .ValueChanged);
}

/// A dropdown's choice, a row of its popup list: selects it among the other rows (SelectedTag), shows its text on the
/// dropdown's button (the entity the popup was opened against) and closes the popup. ValueChanged goes to the button and
/// everything it is inside, where the dropdown sits, unless the row was already the choice. See Chosen and ChosenIndex
pub fn Choose(engine_context: *EngineContext, row: Entity) !void {
    const popup = PopupContaining(row);
    const changed = try SelectAmongSiblings(engine_context, row);
    const popups = &engine_context.mUIManager.mPopupSystem;
    const opener = if (popup) |p| popups.OpenerOf(p) else null;
    if (opener) |button| {
        try ShowChoice(engine_context, button, row);
        if (changed) try engine_context.mUIManager.SendToChain(engine_context, button, .ValueChanged);
    }
    if (popup) |p| try popups.Close(engine_context, p);
}

/// A dropdown's choice: the selected row of the list its button opens (PopupRefComponent). Null if nothing is chosen
pub fn Chosen(dropdown: Entity) ?Entity {
    const popup = PopupOf(dropdown) orelse return null;
    return FirstSelected(popup);
}

/// Where a dropdown's choice is among its rows, 0 for the first. Null if nothing is chosen
pub fn ChosenIndex(dropdown: Entity) ?usize {
    const row = Chosen(dropdown) orelse return null;
    const parent = Parent(row) orelse return null;
    var index: usize = 0;
    var siblings = parent.GetIterator(.Child);
    while (siblings.next()) |sibling| : (index += 1) {
        if (sibling.mID == row.mID) return index;
    }
    return null;
}

/// Shows the choice at `index` on a dropdown, without telling anyone: its row selected among the others and its text on
/// the button. For showing a value it already has, not for picking one (Choose)
pub fn ShowChosen(engine_context: *EngineContext, dropdown: Entity, index: usize) !void {
    if (ChosenIndex(dropdown) == index) return;
    const popup = PopupOf(dropdown) orelse return;
    var position: usize = 0;
    var rows = popup.GetIterator(.Child);
    while (rows.next()) |row| : (position += 1) {
        if (position != index) continue;
        _ = try SelectAmongSiblings(engine_context, row);
        try ShowChoice(engine_context, dropdown, row);
        return;
    }
}

/// Shows `color` on a color field, without telling anyone: its channels and its swatch. For showing a value it already
/// has, not for setting one (SetColor)
pub fn ShowColor(color_field: Entity, color: Vec4(f32)) void {
    const channels = [4]f32{ color.x, color.y, color.z, color.w };
    var index: usize = 0;
    var children = color_field.GetIterator(.Child);
    while (children.next()) |child| {
        if (index == channels.len) break;
        const attrib = child.GetComponentMut(AttribComponent) orelse continue;
        attrib.mData.SetFromFloat(channels[index]);
        index += 1;
    }
    UpdateSwatch(color_field);
}

/// Puts a row's text on a dropdown's button, the way a choice shows: both through their label (UIManager.LabelOf)
pub fn ShowChoice(engine_context: *EngineContext, dropdown: Entity, row: Entity) !void {
    const from = UIManager.LabelOf(row) orelse return;
    const to = UIManager.LabelOf(dropdown) orelse return;
    try to.GetComponentMut(TextComponent).?.SetText(engine_context, from.GetComponent(TextComponent).?.mText.items);
    try to.MarkLayoutDirty(engine_context);
}

/// Opens the popup the entity's PopupRefComponent names against the entity, or closes it if it is open: a dropdown's
/// button, a menu bar's menu. Nothing happens without a popup to open
pub fn TogglePopup(engine_context: *EngineContext, opener: Entity) !void {
    const popup = PopupOf(opener) orelse return;
    const popups = &engine_context.mUIManager.mPopupSystem;
    if (popups.IsOpen(popup)) {
        try popups.Close(engine_context, popup);
    } else {
        try popups.Open(engine_context, popup, .{ .Opener = opener });
    }
}

/// Opens the popup the entity's PopupRefComponent names where the pointer is: a right-click menu. Against the entity if
/// where the pointer is can't be worked out. Returns whether it had a popup to open
pub fn OpenContextMenu(engine_context: *EngineContext, opener: Entity) !bool {
    const popup = PopupOf(opener) orelse return false;
    const at: PopupSystem.At = if (PopupSystem.PointerPoint(popup, engine_context.mPointerSystem.mInput)) |point| .{ .Point = point } else .{ .Opener = opener };
    try engine_context.mUIManager.mPopupSystem.Open(engine_context, popup, at);
    return true;
}

/// Closes every open popup: a menu item, once it is picked
pub fn ClosePopups(engine_context: *EngineContext) !void {
    try engine_context.mUIManager.mPopupSystem.CloseAll(engine_context);
}

/// What a folding header's arrow shows while what it folds is open, and while it is folded away
pub const ARROW_OPEN = "v";
pub const ARROW_FOLDED = ">";

/// Folds `content` away, or out again, through its layout item (given one if it has none), and turns `arrow` (an
/// entity showing text, or one with a label in it) to ARROW_FOLDED or ARROW_OPEN to match: a tree node's content, a
/// collapsing header's. uninit for no arrow. Nothing happens without content
pub fn Fold(engine_context: *EngineContext, content: Entity, arrow: Entity) !void {
    if (!content.IsActive()) return;
    const item = content.GetComponentMut(LayoutItemComponent) orelse try content.AddComponent(engine_context, LayoutItemComponent{});
    item.mCollapsed = !item.mCollapsed;
    const folded = item.mCollapsed;
    try content.MarkLayoutDirty(engine_context);
    if (arrow.IsActive()) try SetText(engine_context, arrow, if (folded) ARROW_FOLDED else ARROW_OPEN);
}

/// A menu item was picked: every menu closes. What picking it does is the item's own script
pub const PickMenuItem = ClosePopups;

/// The pointer moved onto a menu item: the submenus open off its menu close, unless it is the row that opened them
pub fn HoverMenuItem(engine_context: *EngineContext, item: Entity) !void {
    const menu = PopupContaining(item) orelse return;
    try engine_context.mUIManager.mPopupSystem.CloseAbovePopup(engine_context, menu);
}

/// Opens the submenu a menu row's PopupRefComponent names beside it, on top of the menu the row is in, closing any other
/// submenu open off that menu. Moving onto the row or clicking it does this
pub fn OpenSubmenu(engine_context: *EngineContext, row: Entity) !void {
    const submenu = PopupOf(row) orelse return;
    try engine_context.mUIManager.mPopupSystem.Open(engine_context, submenu, .{ .Opener = row });
}

/// The pointer moved onto a menu bar's menu button: if another menu of the same bar is open, this one opens instead,
/// the way moving along a menu bar switches between its menus
pub fn HoverMenuBarButton(engine_context: *EngineContext, button: Entity) !void {
    const popup = PopupOf(button) orelse return;
    const popups = &engine_context.mUIManager.mPopupSystem;
    if (popups.IsOpen(popup)) return;
    const bar = Parent(button) orelse return;
    for (popups.OpenPopups()) |open| {
        const opener = switch (open.mAt) {
            .Opener => |opener| opener,
            .Point => continue,
        };
        if (!opener.IsActive() or opener.mID == button.mID) continue;
        const opener_bar = Parent(opener) orelse continue;
        if (opener_bar.mID == bar.mID and opener_bar.mManager == bar.mManager) {
            try popups.Open(engine_context, popup, .{ .Opener = button });
            return;
        }
    }
}

/// Puts `text` on a label (or the label in `entity`, see UIManager.LabelOf), if it doesn't say that already: new text has
/// to be laid out again, so a label that already says it is left alone
pub fn SetText(engine_context: *EngineContext, entity: Entity, text: []const u8) !void {
    const label = UIManager.LabelOf(entity) orelse return;
    const text_component = label.GetComponentMut(TextComponent).?;
    if (std.mem.eql(u8, text_component.mText.items, text)) return;
    try text_component.SetText(engine_context, text);
    try label.MarkLayoutDirty(engine_context);
}

/// Greys an entity out (DisabledTag), or makes it usable again: a menu item that can't be used right now
pub fn SetDisabled(engine_context: *EngineContext, entity: Entity, disabled: bool) !void {
    if (disabled == entity.HasComponent(EntityComponents.DisabledTag)) return;
    if (disabled) {
        _ = try entity.AddComponent(engine_context, EntityComponents.DisabledTag{});
    } else {
        try entity.RemoveComponentSync(engine_context, EntityComponents.DisabledTag);
    }
}

/// Checks or unchecks a checkable menu item: SelectedTag on its check box, its last child if that is a quad (see
/// Widgets.MenuItem). Nothing happens for an item with no check box
pub fn SetChecked(engine_context: *EngineContext, item: Entity, checked: bool) !void {
    const check = CheckOf(item) orelse return;
    if (checked == check.HasComponent(SelectedTag)) return;
    if (checked) {
        _ = try check.AddComponent(engine_context, SelectedTag{});
    } else {
        try check.RemoveComponentSync(engine_context, SelectedTag);
    }
}

/// Whether a checkable menu item is checked. False for an item with no check box
pub fn IsChecked(item: Entity) bool {
    const check = CheckOf(item) orelse return false;
    return check.HasComponent(SelectedTag);
}

/// The popup an opener's PopupRefComponent names, null if it names none that is still there
pub fn PopupOf(opener: Entity) ?Entity {
    const popup_ref = UIManager.GetUIComponent(opener, PopupRefComponent) orelse return null;
    return if (popup_ref.mPopup.IsActive()) popup_ref.mPopup else null;
}

/// A color field's color: its channels, the children with an AttribComponent, as red, green, blue and alpha (each 0 to
/// 1). A channel it hasn't is 1
pub fn ColorOf(color_field: Entity) Vec4(f32) {
    var channels = [4]f32{ 1, 1, 1, 1 };
    var index: usize = 0;
    var children = color_field.GetIterator(.Child);
    while (children.next()) |child| {
        if (index == channels.len) break;
        const attrib = child.GetComponent(AttribComponent) orelse continue;
        channels[index] = @floatCast(attrib.mData.AsFloat());
        index += 1;
    }
    return .{ .x = channels[0], .y = channels[1], .z = channels[2], .w = channels[3] };
}

/// Sets a color field's channels to `color` (each kept within its number field's limits, sending ValueChanged for each
/// that changes) and shows it in its swatch
pub fn SetColor(engine_context: *EngineContext, color_field: Entity, color: Vec4(f32)) !void {
    const channels = [4]f32{ color.x, color.y, color.z, color.w };
    var index: usize = 0;
    var children = color_field.GetIterator(.Child);
    while (children.next()) |child| {
        if (index == channels.len) break;
        if (!child.HasComponent(AttribComponent)) continue;
        try SetValue(engine_context, child, channels[index]);
        index += 1;
    }
    UpdateSwatch(color_field);
}

/// Shows a color field's color in its swatch: its child with a quad and no AttribComponent. A color field's stock script
/// calls it whenever one of its channels changes
pub fn UpdateSwatch(color_field: Entity) void {
    const color = ColorOf(color_field);
    var children = color_field.GetIterator(.Child);
    while (children.next()) |child| {
        if (child.HasComponent(AttribComponent)) continue;
        if (!child.HasComponent(ShapeComponent)) continue;
        const surface = child.GetComponentMut(SurfaceComponent) orelse continue;
        surface.mTexOptions.mColor = color;
        surface.mTexOptions.mIsTransparent = color.w < 1;
        return;
    }
}

/// SelectedTag on the entity and off every sibling that had it. Returns whether that changed anything
fn SelectAmongSiblings(engine_context: *EngineContext, entity: Entity) !bool {
    if (entity.HasComponent(SelectedTag)) return false;
    if (Parent(entity)) |parent| {
        var siblings = parent.GetIterator(.Child);
        while (siblings.next()) |sibling| {
            if (sibling.mID != entity.mID and sibling.HasComponent(SelectedTag)) try sibling.RemoveComponentSync(engine_context, SelectedTag);
        }
    }
    _ = try entity.AddComponent(engine_context, SelectedTag{});
    return true;
}

/// The smallest a split's pane gets by dragging its divider, in the split's units (canvas units in an overlay)
pub const MIN_PANE_SIZE: f32 = 40;

/// Moves a split's divider (Widgets.Split) by `delta`, which is how far the pointer dragged it: the pane with a fixed
/// size along the split grows or shrinks by that much, and the other pane takes the rest. Neither pane goes below
/// MIN_PANE_SIZE, as far as their last laid out sizes tell
pub fn DragDivider(engine_context: *EngineContext, divider: Entity, delta: Vec3(f32)) !void {
    const split = Parent(divider) orelse return;
    const direction = (split.GetComponent(LayoutComponent) orelse return).mDirection;
    var panes = split.GetIterator(.Child);
    const first = panes.next() orelse return;
    _ = panes.next() orelse return; //the divider
    const second = panes.next() orelse return;

    //towards the second pane: right in a row, down in a column, which is -y on a canvas
    const moved = switch (direction) {
        .Row => delta.x,
        .Column => -delta.y,
        .Grid => return,
    };
    if (moved == 0) return;
    const first_item = first.GetComponentMut(LayoutItemComponent) orelse return;
    const second_item = second.GetComponentMut(LayoutItemComponent) orelse return;
    const along_first = AlongAxis(first_item, direction);
    const along_second = AlongAxis(second_item, direction);
    const total = SizeAlong(first_item.mComputedSize, direction) + SizeAlong(second_item.mComputedSize, direction);

    //the fixed pane is the one that keeps its size when the window does, the other fills what is left
    if (along_first.* == .Fixed) {
        along_first.* = .{ .Fixed = ClampPane(along_first.Fixed + moved, total) };
    } else if (along_second.* == .Fixed) {
        along_second.* = .{ .Fixed = ClampPane(along_second.Fixed - moved, total) };
    } else return;
    try split.MarkLayoutDirty(engine_context);
}

/// Shows a tab's page and hides the other pages beside it (Widgets.Tabs): the tab is selected among the tab bar's tabs
/// (SelectedTag, the theme's "Tab" Selected color), and `page` is the one of its siblings not collapsed. ValueChanged
/// goes to the tab and everything it is inside, unless it was already the one shown
pub fn SelectTab(engine_context: *EngineContext, tab: Entity, page: Entity) !void {
    if (page.IsActive()) {
        if (Parent(page)) |pages| {
            var children = pages.GetIterator(.Child);
            while (children.next()) |other| {
                const item = other.GetComponentMut(LayoutItemComponent) orelse continue;
                item.mCollapsed = other.mID != page.mID;
            }
            try pages.MarkLayoutDirty(engine_context);
        }
    }
    try Select(engine_context, tab);
}

/// How far in front of the rest of its scene the backmost floating window sits, and how much further each one in front
/// of it does. Every entity inside a window sits a little in front of it (Widgets.DEPTH_STEP for each level in), which
/// has to stay under the step to the next window, and every popup (Widgets.POPUP_DEPTH) goes in front of them all
pub const WINDOW_DEPTH: f32 = 0.2;
pub const WINDOW_DEPTH_STEP: f32 = 0.2;

/// Brings a floating window (Widgets.FloatingWindow) in front of the other floating windows of its scene: they keep the
/// order they were in behind it
pub fn RaiseWindow(engine_context: *EngineContext, window: Entity) !void {
    if (!window.IsActive()) return;
    const scene = window.GetComponent(EntitySceneComponent).?.mScene;

    //the scene's other windows, back to front
    var others: std.ArrayList(Entity) = .empty;
    const ui_manager = &engine_context.mUIManager;
    const element_ids = try ui_manager.GetGroup(engine_context.FrameAllocator(), .{ .Component = FloatingWindowComponent });
    for (element_ids.items) |element_id| {
        const other = (UIElement{ .mID = element_id, .mManager = ui_manager }).GetOwner();
        if (!other.IsIDValid() or !other.IsActive() or other.mManager != window.mManager or other.mID == window.mID) continue;
        if (other.GetComponent(EntitySceneComponent).?.mScene.mID != scene.mID) continue;
        try others.append(engine_context.FrameAllocator(), other);
    }
    std.mem.sort(Entity, others.items, {}, struct {
        fn Behind(_: void, a: Entity, b: Entity) bool {
            return DepthOf(a) < DepthOf(b);
        }
    }.Behind);

    for (others.items, 0..) |other, i| try SetDepth(engine_context, other, WINDOW_DEPTH + @as(f32, @floatFromInt(i)) * WINDOW_DEPTH_STEP);
    try SetDepth(engine_context, window, WINDOW_DEPTH + @as(f32, @floatFromInt(others.items.len)) * WINDOW_DEPTH_STEP);
}

/// Moves a floating window by `delta` (how far its title bar was dragged): its anchored offset
pub fn MoveWindow(engine_context: *EngineContext, window: Entity, delta: Vec3(f32)) !void {
    if (!window.IsActive()) return;
    const item = window.GetComponentMut(LayoutItemComponent) orelse return;
    switch (item.mPlacement) {
        .Anchored => |*anchoring| anchoring.Offset = .{ .x = anchoring.Offset.x + delta.x, .y = anchoring.Offset.y + delta.y },
        .Flow => return,
    }
    try window.MarkLayoutDirty(engine_context);
}

/// Hides a floating window, through its layout item
pub fn CloseWindow(engine_context: *EngineContext, window: Entity) !void {
    if (!window.IsActive()) return;
    const item = window.GetComponentMut(LayoutItemComponent) orelse return;
    if (item.mCollapsed) return;
    item.mCollapsed = true;
    try window.MarkLayoutDirty(engine_context);
}

/// Shows a floating window again, in front of the others
pub fn OpenWindow(engine_context: *EngineContext, window: Entity) !void {
    const item = window.GetComponentMut(LayoutItemComponent) orelse return;
    if (item.mCollapsed) {
        item.mCollapsed = false;
        try window.MarkLayoutDirty(engine_context);
    }
    try RaiseWindow(engine_context, window);
}

/// Whether a floating window is shown
pub fn IsWindowOpen(window: Entity) bool {
    const item = window.GetComponent(LayoutItemComponent) orelse return true;
    return !item.mCollapsed;
}

fn DepthOf(entity: Entity) f32 {
    return entity.GetComponent(TransformComponent).?.GetTranslation().z;
}

/// Moves an entity to `depth`, leaving where it is across: that is layout's
fn SetDepth(engine_context: *EngineContext, entity: Entity, depth: f32) !void {
    var translation = entity.GetComponent(TransformComponent).?.GetTranslation();
    if (translation.z == depth) return;
    translation.z = depth;
    try entity.SetTranslation(engine_context, translation);
}

/// A pane's size setting along a split's direction
fn AlongAxis(item: *LayoutItemComponent, direction: @import("Layout.zig").Direction) *@import("Layout.zig").Sizing {
    return if (direction == .Row) &item.mWidth else &item.mHeight;
}

fn SizeAlong(size: @import("../Math/MathTypes.zig").Vec2(f32), direction: @import("Layout.zig").Direction) f32 {
    return if (direction == .Row) size.x else size.y;
}

/// A fixed pane's size kept so both panes of a split are at least MIN_PANE_SIZE, `total` being both together. A split
/// that isn't laid out yet (total 0) only keeps the fixed pane's minimum
fn ClampPane(size: f32, total: f32) f32 {
    const most = if (total > 0) @max(total - MIN_PANE_SIZE, MIN_PANE_SIZE) else std.math.floatMax(f32);
    return std.math.clamp(size, MIN_PANE_SIZE, most);
}

/// A menu item's check box: its last child, if that is a quad
fn CheckOf(item: Entity) ?Entity {
    var last: ?Entity = null;
    var children = item.GetIterator(.Child);
    while (children.next()) |child| last = child;
    const check = last orelse return null;
    return if (check.HasComponent(ShapeComponent)) check else null;
}

/// The nearest entity above `entity` whose UI element has a SelectionGroupComponent
fn GroupOf(entity: Entity) ?Entity {
    var current = Parent(entity) orelse return null;
    while (true) {
        if (UIManager.HasUIComponent(current, SelectionGroupComponent)) return current;
        current = Parent(current) orelse return null;
    }
}

/// SelectedTag off everything in `root`'s tree, `root` itself not counted
fn UnselectTree(engine_context: *EngineContext, root: Entity) !void {
    var children = root.GetIterator(.Child);
    while (children.next()) |child| {
        if (child.HasComponent(SelectedTag)) try child.RemoveComponentSync(engine_context, SelectedTag);
        try UnselectTree(engine_context, child);
    }
}

/// The popup root the entity is in: itself or the nearest entity above it whose UI element has a PopupComponent
fn PopupContaining(entity: Entity) ?Entity {
    var current = entity;
    while (true) {
        if (UIManager.HasUIComponent(current, PopupComponent)) return current;
        current = Parent(current) orelse return null;
    }
}

/// The first entity with SelectedTag in `root`'s tree, `root` itself not counted
fn FirstSelected(root: Entity) ?Entity {
    var children = root.GetIterator(.Child);
    while (children.next()) |child| {
        if (child.HasComponent(SelectedTag)) return child;
        if (FirstSelected(child)) |found| return found;
    }
    return null;
}

fn Parent(entity: Entity) ?Entity {
    const child_component = entity.GetComponent(EntityChildComponent) orelse return null;
    return Entity{ .mID = child_component.mParent, .mManager = entity.mManager };
}


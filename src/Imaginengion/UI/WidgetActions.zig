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
const PopupRefComponent = @import("../ECSComponents/UIComponents.zig").PopupRefComponent;
const ECSComponents = @import("../ECS/Components.zig");
const EntityChildComponent = ECSComponents.ChildComponent(Entity.Type);
const EntityParentComponent = ECSComponents.ParentComponent(Entity.Type);

/// Checked or unchecked: adds `SelectedTag` to the entity, or takes it off. ValueChanged goes to it and its parents
pub fn Toggle(engine_context: *EngineContext, entity: Entity) !void {
    if (entity.HasComponent(SelectedTag)) {
        //at once, so it is drawn unchecked this frame
        try entity.RemoveComponentSync(engine_context, SelectedTag);
    } else {
        _ = try entity.AddComponent(engine_context, SelectedTag{});
    }
    try engine_context.mUIManager.SendToChain(engine_context, entity, .ValueChanged);
}

/// The one picked out of its siblings, like a row of a list: `SelectedTag` on the entity, and off every sibling that had
/// it. ValueChanged goes to it and its parents, unless it was already the selected one
pub fn Select(engine_context: *EngineContext, entity: Entity) !void {
    if (entity.HasComponent(SelectedTag)) return;
    if (Parent(entity)) |parent| {
        var siblings = parent.GetIterator(.Child);
        while (siblings.next()) |sibling| {
            if (sibling.mID != entity.mID and sibling.HasComponent(SelectedTag)) try sibling.RemoveComponentSync(engine_context, SelectedTag);
        }
    }
    _ = try entity.AddComponent(engine_context, SelectedTag{});
    try engine_context.mUIManager.SendToChain(engine_context, entity, .ValueChanged);
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
/// where the pointer is can't be worked out
pub fn OpenContextMenu(engine_context: *EngineContext, opener: Entity) !void {
    const popup = PopupOf(opener) orelse return;
    const at: PopupSystem.At = if (PopupSystem.PointerPoint(popup, engine_context.mPointerSystem.mInput)) |point| .{ .Point = point } else .{ .Opener = opener };
    try engine_context.mUIManager.mPopupSystem.Open(engine_context, popup, at);
}

/// Closes every open popup: a menu item, once it is picked
pub fn ClosePopups(engine_context: *EngineContext) !void {
    try engine_context.mUIManager.mPopupSystem.CloseAll(engine_context);
}

/// Folds the entity right after this one away, or out again: a tree node's header and its content. Through the
/// content's layout item, which it is given if it has none. Nothing happens for the last of its siblings
pub fn CollapseNext(engine_context: *EngineContext, entity: Entity) !void {
    const next = NextSibling(entity) orelse return;
    const item = next.GetComponent(LayoutItemComponent) orelse try next.AddComponent(engine_context, LayoutItemComponent{});
    item.mCollapsed = !item.mCollapsed;
    try next.MarkLayoutDirty(engine_context);
}

/// The popup an opener's PopupRefComponent names, null if it names none that is still there
pub fn PopupOf(opener: Entity) ?Entity {
    const popup_ref = UIManager.GetUIComponent(opener, PopupRefComponent) orelse return null;
    return if (popup_ref.mPopup.IsActive()) popup_ref.mPopup else null;
}

fn Parent(entity: Entity) ?Entity {
    const child_component = entity.GetComponent(EntityChildComponent) orelse return null;
    return Entity{ .mID = child_component.mParent, .mManager = entity.mManager };
}

/// The sibling after `entity`, null if it is the last one: siblings are a ring, which the parent's first child closes
fn NextSibling(entity: Entity) ?Entity {
    const child_component = entity.GetComponent(EntityChildComponent) orelse return null;
    const parent = Parent(entity) orelse return null;
    const first = parent.GetComponent(EntityParentComponent).?.mFirstEntity;
    if (child_component.mNext == first or child_component.mNext == entity.mID) return null;
    return Entity{ .mID = child_component.mNext, .mManager = entity.mManager };
}

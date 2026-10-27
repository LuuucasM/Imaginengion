const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const ScriptResult = @import("IM").ScriptResult;
const PointerEvent = @import("IM").PointerEvent;
const WidgetActions = @import("IM").WidgetActions;
const EntityComponents = @import("IM").EntityComponents;
const UIComponents = @import("IM").UIComponents;
const In = @import("IM").In;
const UIECS = @import("IM").UIECS;
const Submenu = @This();

/// Stock widget script: a menu row that opens a submenu beside it, the popup its UI element's PopupRefComponent names.
/// Moving onto it or clicking it opens the submenu (see WidgetActions.OpenSubmenu)
/// Hands everything on (.Continue): the entity's own scripts and the ones it is inside still hear it
pub const OnPointerEvent = struct {
    /// What it touches, through WidgetActions.OpenSubmenu: the submenu through its UI element, opened by its layout item
    pub const Reads = &.{ EntityComponents.UIElementComponent, In(UIECS, UIComponents.PopupRefComponent) };
    pub const Writes = &.{EntityComponents.LayoutItemComponent};

    pub fn Run(_: *Submenu, engine_context: *EngineContext, owner: Entity, event: *const PointerEvent) ScriptResult {
        const opens = switch (event.*) {
            .PointerClicked => |click| click.mButton == .BUTTON_LEFT,
            .PointerEnter => true,
            else => false,
        };
        if (opens) WidgetActions.OpenSubmenu(engine_context, owner) catch |err| std.log.err("Submenu script: {s}", .{@errorName(err)});
        return .Continue;
    }
};

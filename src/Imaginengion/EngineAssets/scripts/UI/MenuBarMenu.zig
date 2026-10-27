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
const MenuBarMenu = @This();

/// Stock widget script: a menu bar's menu button. Clicking it opens its menu, the popup its UI element's
/// PopupRefComponent names, or closes it (see WidgetActions.TogglePopup). Moving onto it while another menu of the same
/// bar is open opens this one instead (WidgetActions.HoverMenuBarButton)
/// Hands everything on (.Continue): the entity's own scripts and the ones it is inside still hear it
pub const OnPointerEvent = struct {
    /// What it touches, through WidgetActions.TogglePopup and HoverMenuBarButton: the popup through its UI element, opened and closed by its layout item
    pub const Reads = &.{ EntityComponents.UIElementComponent, In(UIECS, UIComponents.PopupRefComponent) };
    pub const Writes = &.{EntityComponents.LayoutItemComponent};

    pub fn Run(_: *MenuBarMenu, engine_context: *EngineContext, owner: Entity, event: *const PointerEvent) ScriptResult {
        switch (event.*) {
            .PointerClicked => |click| {
                if (click.mButton == .BUTTON_LEFT) {
                    WidgetActions.TogglePopup(engine_context, owner) catch |err| std.log.err("MenuBarMenu script: {s}", .{@errorName(err)});
                }
            },
            .PointerEnter => {
                WidgetActions.HoverMenuBarButton(engine_context, owner) catch |err| std.log.err("MenuBarMenu script: {s}", .{@errorName(err)});
            },
            else => {},
        }
        return .Continue;
    }
};

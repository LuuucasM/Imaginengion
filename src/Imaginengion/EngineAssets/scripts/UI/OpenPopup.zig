const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const ScriptResult = @import("IM").ScriptResult;
const PointerEvent = @import("IM").PointerEvent;
const WidgetActions = @import("IM").WidgetActions;
const EntityComponents = @import("IM").EntityComponents;

/// What it touches, through WidgetActions.TogglePopup: the popup through its UI element, opened and closed by its layout item
pub const Reads = &.{EntityComponents.UIElementComponent};
pub const Writes = &.{EntityComponents.LayoutItemComponent};

/// Stock widget script: clicking the entity opens the popup its UI element's PopupRefComponent names against it, or
/// closes it again, a dropdown or a menu bar's menu (see WidgetActions.TogglePopup)
/// Hands the click on (.Continue): the entity's own scripts and the ones it is inside still hear it
pub fn OnPointerEvent(_: *@This(), engine_context: *EngineContext, owner: Entity, event: *const PointerEvent) ScriptResult {
    switch (event.*) {
        .PointerClicked => |click| {
            if (click.mButton == .BUTTON_LEFT) {
                WidgetActions.TogglePopup(engine_context, owner) catch |err| std.log.err("OpenPopup script: {s}", .{@errorName(err)});
            }
        },
        else => {},
    }
    return .Continue;
}

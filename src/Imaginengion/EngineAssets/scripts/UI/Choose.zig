const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const ScriptResult = @import("IM").ScriptResult;
const PointerEvent = @import("IM").PointerEvent;
const WidgetActions = @import("IM").WidgetActions;
const EntityComponents = @import("IM").EntityComponents;

/// What it touches, through WidgetActions.Choose: finds the popup it is in through UI elements, puts the row's text on the button, and closes the popup (folding its layout item)
pub const Reads = &.{EntityComponents.UIElementComponent};
pub const Writes = &.{ EntityComponents.LayoutItemComponent, EntityComponents.TextComponent };

/// Stock widget script: clicking the entity makes it a dropdown's choice, a row of the dropdown's popup list (see
/// WidgetActions.Choose). It is selected among the other rows, its text shows on the dropdown's button, the popup
/// closes, and the button and everything it is inside get a ValueChanged
/// Hands the click on (.Continue): the entity's own scripts and the ones it is inside still hear it
pub fn OnPointerEvent(_: *@This(), engine_context: *EngineContext, owner: Entity, event: *const PointerEvent) ScriptResult {
    switch (event.*) {
        .PointerClicked => |click| {
            if (click.mButton == .BUTTON_LEFT) {
                WidgetActions.Choose(engine_context, owner) catch |err| std.log.err("Choose script: {s}", .{@errorName(err)});
            }
        },
        else => {},
    }
    return .Continue;
}

const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const ScriptResult = @import("IM").ScriptResult;
const PointerEvent = @import("IM").PointerEvent;
const WidgetActions = @import("IM").WidgetActions;

/// Stock widget script: a tab of a tab bar (see Widgets.Tabs). Clicking it shows its page and hides the others
/// (WidgetActions.SelectTab)
/// Hands the click on (.Continue): the entity's own scripts and the ones it is inside still hear it
pub fn OnPointerEvent(_: *@This(), engine_context: *EngineContext, owner: Entity, event: *const PointerEvent) ScriptResult {
    switch (event.*) {
        .PointerClicked => |click| {
            if (click.mButton == .BUTTON_LEFT) {
                WidgetActions.SelectTab(engine_context, owner) catch |err| std.log.err("Tab script: {s}", .{@errorName(err)});
            }
        },
        else => {},
    }
    return .Continue;
}

const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const ScriptResult = @import("IM").ScriptResult;
const PointerEvent = @import("IM").PointerEvent;
const WidgetActions = @import("IM").WidgetActions;

/// Stock widget script: clicking the entity selects it and unselects its siblings, a row of a list (see
/// WidgetActions.Select). Selected is SelectedTag on it, and selecting it sends it and everything it is inside a
/// ValueChanged
/// Hands the click on (.Continue): the entity's own scripts and the ones it is inside still hear it
pub fn OnPointerEvent(_: *@This(), engine_context: *EngineContext, owner: Entity, event: *const PointerEvent) ScriptResult {
    switch (event.*) {
        .PointerClicked => |click| {
            if (click.mButton == .BUTTON_LEFT) {
                WidgetActions.Select(engine_context, owner) catch |err| std.log.err("Select script: {s}", .{@errorName(err)});
            }
        },
        else => {},
    }
    return .Continue;
}

const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const ScriptResult = @import("IM").ScriptResult;
const PointerEvent = @import("IM").PointerEvent;
const WidgetActions = @import("IM").WidgetActions;

/// Stock widget script: clicking the entity folds away the entity right after it, or brings it back, a tree node's
/// header and its content (see WidgetActions.CollapseNext)
/// Hands the click on (.Continue): the entity's own scripts and the ones it is inside still hear it
pub fn OnPointerEvent(_: *@This(), engine_context: *EngineContext, owner: Entity, event: *const PointerEvent) ScriptResult {
    switch (event.*) {
        .PointerClicked => |click| {
            if (click.mButton == .BUTTON_LEFT) {
                WidgetActions.CollapseNext(engine_context, owner) catch |err| std.log.err("Collapse script: {s}", .{@errorName(err)});
            }
        },
        else => {},
    }
    return .Continue;
}

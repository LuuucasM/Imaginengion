const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const ScriptResult = @import("IM").ScriptResult;
const PointerEvent = @import("IM").PointerEvent;
const WidgetActions = @import("IM").WidgetActions;

/// Stock widget script: clicking the entity folds the entity right after it away, or out again, and turns its arrow: a
/// collapsing header (see WidgetActions.FoldNext)
/// Hands the click on (.Continue): the entity's own scripts and the ones it is inside still hear it
pub fn OnPointerEvent(_: *@This(), engine_context: *EngineContext, owner: Entity, event: *const PointerEvent) ScriptResult {
    switch (event.*) {
        .PointerClicked => |click| {
            if (click.mButton == .BUTTON_LEFT) {
                WidgetActions.FoldNext(engine_context, owner) catch |err| std.log.err("Fold script: {s}", .{@errorName(err)});
            }
        },
        else => {},
    }
    return .Continue;
}

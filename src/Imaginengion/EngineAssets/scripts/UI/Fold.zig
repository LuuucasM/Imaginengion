const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const ScriptResult = @import("IM").ScriptResult;
const PointerEvent = @import("IM").PointerEvent;
const WidgetActions = @import("IM").WidgetActions;

/// What clicking folds away and out again
mContent: Entity = .uninit,
/// What shows whether it is folded (WidgetActions.ARROW_OPEN or ARROW_FOLDED): the arrow's text, or an entity with it
/// in. None needed
mArrow: Entity = .uninit,

/// Stock widget script: clicking the entity folds its content away, or out again, and turns its arrow: a collapsing
/// header (see WidgetActions.Fold)
/// Hands the click on (.Continue): the entity's own scripts and the ones it is inside still hear it
pub fn OnPointerEvent(self: *@This(), engine_context: *EngineContext, owner: Entity, event: *const PointerEvent) ScriptResult {
    _ = owner;
    switch (event.*) {
        .PointerClicked => |click| {
            if (click.mButton == .BUTTON_LEFT) {
                WidgetActions.Fold(engine_context, self.mContent, self.mArrow) catch |err| std.log.err("Fold script: {s}", .{@errorName(err)});
            }
        },
        else => {},
    }
    return .Continue;
}

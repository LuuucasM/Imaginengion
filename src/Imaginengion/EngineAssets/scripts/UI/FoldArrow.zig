const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const ScriptResult = @import("IM").ScriptResult;
const PointerEvent = @import("IM").PointerEvent;
const WidgetActions = @import("IM").WidgetActions;
const FoldArrow = @This();

/// What clicking the arrow folds away and out again
mContent: Entity = .uninit,

/// Stock widget script: clicking the entity, a tree node's arrow, folds the node's content away or out again and turns
/// the arrow (see WidgetActions.Fold)
/// Keeps the click (.Handled), so the header it is in doesn't also take it as selecting the row
pub fn OnPointerEvent(self: *FoldArrow, engine_context: *EngineContext, owner: Entity, event: *const PointerEvent) ScriptResult {
    switch (event.*) {
        .PointerClicked => |click| {
            if (click.mButton == .BUTTON_LEFT) {
                WidgetActions.Fold(engine_context, self.mContent, owner) catch |err| std.log.err("FoldArrow script: {s}", .{@errorName(err)});
                return .Handled;
            }
        },
        else => {},
    }
    return .Continue;
}

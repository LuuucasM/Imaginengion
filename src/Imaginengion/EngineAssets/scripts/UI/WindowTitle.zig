const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const ScriptType = @import("IM").ScriptType;
const ScriptResult = @import("IM").ScriptResult;
const PointerEvent = @import("IM").PointerEvent;
const WidgetActions = @import("IM").WidgetActions;

/// Stock widget script: a floating window's title bar (see Widgets.FloatingWindow). Dragging it (left button) moves the
/// window (WidgetActions.MoveWindow)
/// Keeps its drag (.Handled), so the window it is in doesn't also take it as a drag of its own
pub export fn Run(engine_context: *EngineContext, self: *const Entity, event: *const PointerEvent) callconv(.c) ScriptResult {
    switch (event.*) {
        .PointerDrag => |drag| {
            if (drag.mButton == .BUTTON_LEFT) {
                WidgetActions.MoveWindow(engine_context, self.*, drag.mDelta) catch |err| std.log.err("WindowTitle script: {s}", .{@errorName(err)});
                return .Handled;
            }
        },
        else => {},
    }
    return .Continue;
}
//Note the following functions are for editor purposes and to not be changed by user or bad things can happen :)
pub export fn GetScriptType() callconv(.c) ScriptType {
    return ScriptType.EntityOnPointerEvent;
}

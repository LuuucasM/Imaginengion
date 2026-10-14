const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const ScriptResult = @import("IM").ScriptResult;
const PointerEvent = @import("IM").PointerEvent;
const WidgetActions = @import("IM").WidgetActions;

/// The window dragging the title bar moves
mWindow: Entity = .uninit,

/// Stock widget script: a floating window's title bar (see Widgets.FloatingWindow). Dragging it (left button) moves the
/// window (WidgetActions.MoveWindow)
/// Keeps its drag (.Handled), so the window it is in doesn't also take it as a drag of its own
pub fn OnPointerEvent(self: *@This(), engine_context: *EngineContext, owner: Entity, event: *const PointerEvent) ScriptResult {
    _ = owner;
    switch (event.*) {
        .PointerDrag => |drag| {
            if (drag.mButton == .BUTTON_LEFT) {
                WidgetActions.MoveWindow(engine_context, self.mWindow, drag.mDelta) catch |err| std.log.err("WindowTitle script: {s}", .{@errorName(err)});
                return .Handled;
            }
        },
        else => {},
    }
    return .Continue;
}

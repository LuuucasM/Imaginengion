const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const ScriptResult = @import("IM").ScriptResult;
const PointerEvent = @import("IM").PointerEvent;
const WidgetActions = @import("IM").WidgetActions;
const CloseWindow = @This();

/// The window clicking hides
mWindow: Entity = .uninit,

/// Stock widget script: a floating window's close button (see Widgets.FloatingWindow). Clicking it hides the window
/// (WidgetActions.CloseWindow)
/// Hands the click on (.Continue): the entity's own scripts and the ones it is inside still hear it
pub fn OnPointerEvent(self: *CloseWindow, engine_context: *EngineContext, owner: Entity, event: *const PointerEvent) ScriptResult {
    _ = owner;
    switch (event.*) {
        .PointerClicked => |click| {
            if (click.mButton == .BUTTON_LEFT) {
                WidgetActions.CloseWindow(engine_context, self.mWindow) catch |err| std.log.err("CloseWindow script: {s}", .{@errorName(err)});
            }
        },
        else => {},
    }
    return .Continue;
}

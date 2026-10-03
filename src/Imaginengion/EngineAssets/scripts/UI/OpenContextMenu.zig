const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const ScriptType = @import("IM").ScriptType;
const ScriptResult = @import("IM").ScriptResult;
const PointerEvent = @import("IM").PointerEvent;
const WidgetActions = @import("IM").WidgetActions;

/// Stock widget script: right clicking the entity opens the popup its UI element's PopupRefComponent names where the
/// pointer is, a right-click menu (see WidgetActions.OpenContextMenu)
/// Hands the click on (.Continue): the entity's own scripts and the ones it is inside still hear it
pub export fn Run(engine_context: *EngineContext, self: *const Entity, event: *const PointerEvent) callconv(.c) ScriptResult {
    switch (event.*) {
        .PointerClicked => |click| {
            if (click.mButton == .BUTTON_RIGHT) {
                WidgetActions.OpenContextMenu(engine_context, self.*) catch |err| std.log.err("OpenContextMenu script: {s}", .{@errorName(err)});
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

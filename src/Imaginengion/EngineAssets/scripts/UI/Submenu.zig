const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const ScriptType = @import("IM").ScriptType;
const ScriptResult = @import("IM").ScriptResult;
const PointerEvent = @import("IM").PointerEvent;
const WidgetActions = @import("IM").WidgetActions;

/// Stock widget script: a menu row that opens a submenu beside it, the popup its UI element's PopupRefComponent names.
/// Moving onto it or clicking it opens the submenu (see WidgetActions.OpenSubmenu)
/// Hands everything on (.Continue): the entity's own scripts and the ones it is inside still hear it
pub export fn Run(engine_context: *EngineContext, self: *const Entity, event: *const PointerEvent) callconv(.c) ScriptResult {
    const opens = switch (event.*) {
        .PointerClicked => |click| click.mButton == .BUTTON_LEFT,
        .PointerEnter => true,
        else => false,
    };
    if (opens) WidgetActions.OpenSubmenu(engine_context, self.*) catch |err| std.log.err("Submenu script: {s}", .{@errorName(err)});
    return .Continue;
}
//Note the following functions are for editor purposes and to not be changed by user or bad things can happen :)
pub export fn GetScriptType() callconv(.c) ScriptType {
    return ScriptType.EntityOnPointerEvent;
}

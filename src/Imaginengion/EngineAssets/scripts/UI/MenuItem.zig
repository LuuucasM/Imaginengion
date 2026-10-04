const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const ScriptType = @import("IM").ScriptType;
const ScriptResult = @import("IM").ScriptResult;
const PointerEvent = @import("IM").PointerEvent;
const WidgetActions = @import("IM").WidgetActions;

/// Stock widget script: a menu item. Clicking it closes every menu (see WidgetActions.PickMenuItem); what picking it
/// does is the item's own script. Moving onto it closes the submenus open off its menu (WidgetActions.HoverMenuItem)
/// Hands everything on (.Continue): the entity's own scripts and the ones it is inside still hear it
pub export fn Run(engine_context: *EngineContext, self: *const Entity, event: *const PointerEvent) callconv(.c) ScriptResult {
    switch (event.*) {
        .PointerClicked => |click| {
            if (click.mButton == .BUTTON_LEFT) {
                WidgetActions.PickMenuItem(engine_context) catch |err| std.log.err("MenuItem script: {s}", .{@errorName(err)});
            }
        },
        .PointerEnter => {
            WidgetActions.HoverMenuItem(engine_context, self.*) catch |err| std.log.err("MenuItem script: {s}", .{@errorName(err)});
        },
        else => {},
    }
    return .Continue;
}
//Note the following functions are for editor purposes and to not be changed by user or bad things can happen :)
pub export fn GetScriptType() callconv(.c) ScriptType {
    return ScriptType.EntityOnPointerEvent;
}

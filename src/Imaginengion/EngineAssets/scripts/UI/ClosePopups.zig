const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const ScriptResult = @import("IM").ScriptResult;
const PointerEvent = @import("IM").PointerEvent;
const WidgetActions = @import("IM").WidgetActions;
const ClosePopups = @This();

/// Stock widget script: clicking the entity closes every open popup, a menu's item once it is picked (see
/// WidgetActions.ClosePopups). Put the item's own script on it too, for what picking it does
/// Hands the click on (.Continue): the entity's own scripts and the ones it is inside still hear it
pub fn OnPointerEvent(_: *ClosePopups, engine_context: *EngineContext, owner: Entity, event: *const PointerEvent) ScriptResult {
    _ = owner;
    switch (event.*) {
        .PointerClicked => |click| {
            if (click.mButton == .BUTTON_LEFT) {
                WidgetActions.ClosePopups(engine_context) catch |err| std.log.err("ClosePopups script: {s}", .{@errorName(err)});
            }
        },
        else => {},
    }
    return .Continue;
}

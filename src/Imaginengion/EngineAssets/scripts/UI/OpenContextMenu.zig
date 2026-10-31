const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const ScriptResult = @import("IM").ScriptResult;
const PointerEvent = @import("IM").PointerEvent;
const WidgetActions = @import("IM").WidgetActions;
const OpenContextMenu = @This();

/// Stock widget script: right clicking the entity opens the popup its UI element's PopupRefComponent names where the
/// pointer is, a right-click menu (see WidgetActions.OpenContextMenu)
/// Keeps a right click that opened its menu (.Handled), so the innermost menu wins: a row's own menu rather than the
/// panel's it is in. Hands on every other click (.Continue)
pub fn OnPointerEvent(_: *OpenContextMenu, engine_context: *EngineContext, owner: Entity, event: *const PointerEvent) ScriptResult {
    switch (event.*) {
        .PointerClicked => |click| {
            if (click.mButton == .BUTTON_RIGHT) {
                const opened = WidgetActions.OpenContextMenu(engine_context, owner) catch |err| blk: {
                    std.log.err("OpenContextMenu script: {s}", .{@errorName(err)});
                    break :blk false;
                };
                if (opened) return .Handled;
            }
        },
        else => {},
    }
    return .Continue;
}

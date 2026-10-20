const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const ScriptResult = @import("IM").ScriptResult;
const PointerEvent = @import("IM").PointerEvent;
const WidgetActions = @import("IM").WidgetActions;
const EntityComponents = @import("IM").EntityComponents;

/// What it touches, through WidgetActions.DragDivider: the split's direction, and the panes' sizes
pub const Reads = &.{EntityComponents.LayoutComponent};
pub const Writes = &.{EntityComponents.LayoutItemComponent};

/// Stock widget script: a split's divider (see Widgets.Split). Dragging it (left button) moves the split
/// (WidgetActions.DragDivider)
/// Keeps its own drag (.Handled), so what the split is in doesn't also take it as a drag of its own
pub fn OnPointerEvent(_: *@This(), engine_context: *EngineContext, owner: Entity, event: *const PointerEvent) ScriptResult {
    switch (event.*) {
        .PointerDrag => |drag| {
            if (drag.mButton == .BUTTON_LEFT and drag.mTarget.mID == owner.mID) {
                WidgetActions.DragDivider(engine_context, owner, drag.mDelta) catch |err| std.log.err("Divider script: {s}", .{@errorName(err)});
                return .Handled;
            }
        },
        else => {},
    }
    return .Continue;
}

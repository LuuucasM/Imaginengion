const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const ScriptResult = @import("IM").ScriptResult;
const PointerEvent = @import("IM").PointerEvent;
const WidgetActions = @import("IM").WidgetActions;
const EntityComponents = @import("IM").EntityComponents;
const WindowTitle = @This();

/// The window dragging the title bar moves
mWindow: Entity = .uninit,

/// Stock widget script: a floating window's title bar (see Widgets.FloatingWindow). Dragging it (left button) moves the
/// window (WidgetActions.MoveWindow)
/// Keeps its drag (.Handled), so the window it is in doesn't also take it as a drag of its own
pub const OnPointerEvent = struct {
    /// What it touches, through WidgetActions.MoveWindow: the window's anchored offset, in its layout item
    pub const Reads = &.{};
    pub const Writes = &.{EntityComponents.LayoutItemComponent};

    pub fn Run(self: *WindowTitle, engine_context: *EngineContext, owner: Entity, event: *const PointerEvent) ScriptResult {
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
};

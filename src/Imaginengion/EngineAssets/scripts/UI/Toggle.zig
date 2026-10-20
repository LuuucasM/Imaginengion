const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const ScriptResult = @import("IM").ScriptResult;
const PointerEvent = @import("IM").PointerEvent;
const WidgetActions = @import("IM").WidgetActions;
const EntityComponents = @import("IM").EntityComponents;

/// What it touches, through WidgetActions.Toggle: shows or folds the check mark's layout item
pub const Reads = &.{};
pub const Writes = &.{EntityComponents.LayoutItemComponent};

/// The check mark shown only while the entity is checked (Widgets.AddCheckMark). None needed: a theme can color the
/// box by its state instead
mMark: Entity = .uninit,

/// Stock widget script: clicking the entity checks or unchecks it, a checkbox's box (see WidgetActions.Toggle).
/// Checked is SelectedTag on it, and each click sends it and everything it is inside a ValueChanged
/// Hands the click on (.Continue): the entity's own scripts and the ones it is inside still hear it
pub fn OnPointerEvent(self: *@This(), engine_context: *EngineContext, owner: Entity, event: *const PointerEvent) ScriptResult {
    switch (event.*) {
        .PointerClicked => |click| {
            if (click.mButton == .BUTTON_LEFT) {
                WidgetActions.Toggle(engine_context, owner, self.mMark) catch |err| std.log.err("Toggle script: {s}", .{@errorName(err)});
            }
        },
        else => {},
    }
    return .Continue;
}

const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const ScriptResult = @import("IM").ScriptResult;
const PointerEvent = @import("IM").PointerEvent;
const WidgetActions = @import("IM").WidgetActions;
const EntityComponents = @import("IM").EntityComponents;

/// What it touches, through WidgetActions.PickMenuItem and HoverMenuItem: the menu through its UI element, popups closed by their layout items
pub const Reads = &.{EntityComponents.UIElementComponent};
pub const Writes = &.{EntityComponents.LayoutItemComponent};

/// Stock widget script: a menu item. Clicking it closes every menu (see WidgetActions.PickMenuItem); what picking it
/// does is the item's own script. Moving onto it closes the submenus open off its menu (WidgetActions.HoverMenuItem)
/// Hands everything on (.Continue): the entity's own scripts and the ones it is inside still hear it
pub fn OnPointerEvent(_: *@This(), engine_context: *EngineContext, owner: Entity, event: *const PointerEvent) ScriptResult {
    switch (event.*) {
        .PointerClicked => |click| {
            if (click.mButton == .BUTTON_LEFT) {
                WidgetActions.PickMenuItem(engine_context) catch |err| std.log.err("MenuItem script: {s}", .{@errorName(err)});
            }
        },
        .PointerEnter => {
            WidgetActions.HoverMenuItem(engine_context, owner) catch |err| std.log.err("MenuItem script: {s}", .{@errorName(err)});
        },
        else => {},
    }
    return .Continue;
}

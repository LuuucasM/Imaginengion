const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const ScriptResult = @import("IM").ScriptResult;
const PointerEvent = @import("IM").PointerEvent;
const WidgetActions = @import("IM").WidgetActions;
const EntityComponents = @import("IM").EntityComponents;
const UIComponents = @import("IM").UIComponents;
const In = @import("IM").In;
const UIECS = @import("IM").UIECS;
const Window = @This();

/// Stock widget script: a floating window (see Widgets.FloatingWindow). Pressing anywhere on it brings it in front of
/// the scene's other floating windows (WidgetActions.RaiseWindow)
/// Hands the press on (.Continue): the entity's own scripts and the ones it is inside still hear it
pub const OnPointerEvent = struct {
    /// What it touches, through WidgetActions.RaiseWindow: the scene's other windows, and each one's depth in its transform
    pub const Reads = &.{
        EntityComponents.EntitySceneComponent,
        EntityComponents.LayoutItemComponent,
        //the floating windows, from the UI's own ECS, and whose window each one is
        In(UIECS, UIComponents.FloatingWindowComponent),
        In(UIECS, UIComponents.ElementOwnerComponent),
    };
    pub const Writes = &.{EntityComponents.TransformComponent};

    pub fn Run(_: *Window, engine_context: *EngineContext, owner: Entity, event: *const PointerEvent) ScriptResult {
        switch (event.*) {
            .PointerPressed => {
                WidgetActions.RaiseWindow(engine_context, owner) catch |err| std.log.err("Window script: {s}", .{@errorName(err)});
            },
            else => {},
        }
        return .Continue;
    }
};

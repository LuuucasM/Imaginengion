const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const ScriptType = @import("IM").ScriptType;
const ScriptResult = @import("IM").ScriptResult;
const PointerEvent = @import("IM").PointerEvent;
const OnPointerEventScript = @This();

/// Function that gets executed for every pointer (mouse) event sent to this entity. Any entity the pointer can be over
/// gets them, in the world as much as in UI: an enemy that lights up when hovered, a door that opens when clicked, a
/// crate that can be dragged, as well as a button or a slot things are dropped in. Events are sent to what the pointer
/// is over and then to each thing that is inside of, so this hears clicks on this entity's children too. Only this
/// entity's own events come here, so there is no need to check who an event is for: switch on what happened. Each
/// event but enter and exit has:
///     mTarget: what the pointer was actually over (this entity, or something inside it)
/// and then, by event:
///     .PointerEnter / .PointerExit: the pointer came over this entity (or something inside it), or left it
///     .PointerPressed / .PointerReleased: mButton went down or came up. mPosition is where, in the world
///     .PointerClicked: mButton went down and came back up in place. mClicks is 2 for a double click
///     .PointerDragStart / .PointerDrag / .PointerDragEnd: mButton went down on this and the pointer is moving.
///         mDelta is how far since the last one and mTotal since it started, in the units this entity is placed in
///     .PointerDropped: mSource, a drag source (DragSourceComponent), was let go on this drop target
/// return .Continue and the entities this one is inside get the event too, and this entity's other pointer scripts
/// return .Handled and it stops here: e.g. a button inside a clickable panel keeps its click from the panel
pub export fn Run(engine_context: *EngineContext, self: *const Entity, event: *const PointerEvent) callconv(.c) ScriptResult {
    _ = engine_context;
    _ = self;

    switch (event.*) {
        .PointerClicked => |click| {
            if (click.mButton == .BUTTON_LEFT) {
                //what clicking it does goes here
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

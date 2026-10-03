const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const ScriptType = @import("IM").ScriptType;
const ScriptResult = @import("IM").ScriptResult;
const UIEvent = @import("IM").UIEvent;
const OnUIEventScript = @This();

/// Function that gets executed for every UI event sent to this entity. Like pointer events, they go to the entity it
/// happened to and then to each one it is inside, so this hears about its children too. Each event has:
///     mEntity: this entity
///     mTarget: the entity it actually happened to
/// and then, by event:
///     .FocusGained / .FocusLost: a text input (TextInputComponent on its UI element) got the keyboard, or lost it
///     .TextChanged: its text was typed into, deleted from, pasted into, or put back by Escape
///     .TextSubmitted: the edit was kept, by Enter or a press somewhere else. Read the text off mTarget's TextComponent
///     .PopupOpened / .PopupClosed: a popup opened or closed. mOpener is what it was opened against, if anything
///     .ValueChanged: a widget's value changed, e.g. a checkbox checked (SelectedTag on mTarget) or a row selected
/// return .Continue and the entities this one is inside get the event too, and this entity's other UI scripts
/// return .Handled and it stops here
pub export fn Run(engine_context: *EngineContext, self: *const Entity, event: *const UIEvent) callconv(.c) ScriptResult {
    _ = engine_context;
    _ = self;

    switch (event.*) {
        .TextSubmitted => |submitted| {
            _ = submitted;
            //what entering the text does goes here
        },
        else => {},
    }
    return .Continue;
}
//Note the following functions are for editor purposes and to not be changed by user or bad things can happen :)
pub export fn GetScriptType() callconv(.c) ScriptType {
    return ScriptType.EntityOnUIEvent;
}

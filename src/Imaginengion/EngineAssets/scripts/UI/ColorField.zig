const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const ScriptType = @import("IM").ScriptType;
const ScriptResult = @import("IM").ScriptResult;
const UIEvent = @import("IM").UIEvent;
const WidgetActions = @import("IM").WidgetActions;

/// Stock widget script: a color field, whose swatch shows its color again whenever one of its channels (the number
/// fields inside it) changes (see WidgetActions.UpdateSwatch). Read the color with WidgetActions.ColorOf
/// Hands the change on (.Continue): the entity's own scripts and the ones it is inside still hear it
pub export fn Run(engine_context: *EngineContext, self: *const Entity, event: *const UIEvent) callconv(.c) ScriptResult {
    _ = engine_context;
    switch (event.*) {
        .ValueChanged => |changed| {
            if (changed.mTarget.mID != self.mID) WidgetActions.UpdateSwatch(self.*);
        },
        else => {},
    }
    return .Continue;
}
//Note the following functions are for editor purposes and to not be changed by user or bad things can happen :)
pub export fn GetScriptType() callconv(.c) ScriptType {
    return ScriptType.EntityOnUIEvent;
}

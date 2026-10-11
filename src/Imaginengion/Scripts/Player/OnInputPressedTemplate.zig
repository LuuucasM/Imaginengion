const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Player = @import("IM").Player;
const ScriptType = @import("IM").ScriptType;
const ScriptResult = @import("IM").ScriptResult;
const KeyboardPressedEvent = @import("IM").KeyboardPressedEvent;
const PlayerOnInputPressedScript = @This();

/// Function that gets executed when a key is pressed, after the entities' input pressed scripts have had it
/// return .Continue and it allows the event to be propegated to the player's other input pressed scripts
/// return .Handled and it will stop at this script
pub export fn Run(engine_context: *EngineContext, self: *const Player, e: *const KeyboardPressedEvent) callconv(.c) ScriptResult {
    _ = engine_context;
    _ = self;
    _ = e;
    //your code goes here
    return .Continue;
}
//Note the following functions are for editor purposes and to not be changed by user or bad things can happen :)
pub export fn GetScriptType() callconv(.c) ScriptType {
    return ScriptType.PlayerInputPressed;
}

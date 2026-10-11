const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Player = @import("IM").Player;
const ScriptType = @import("IM").ScriptType;
const ScriptResult = @import("IM").ScriptResult;
const PlayerOnUpdateScript = @This();

/// Function that gets executed every frame for the player, before the entities' OnUpdate scripts
/// return .Continue and it allows the event to be propegated to other layers/systems
/// return .Handled and it will stop at this layer
pub export fn Run(engine_context: *EngineContext, self: *const Player) callconv(.c) ScriptResult {
    _ = engine_context;
    _ = self;
    //your code goes here
    return .Continue;
}
//Note the following functions are for editor purposes and to not be changed by user or bad things can happen :)
pub export fn GetScriptType() callconv(.c) ScriptType {
    return ScriptType.PlayerOnUpdate;
}

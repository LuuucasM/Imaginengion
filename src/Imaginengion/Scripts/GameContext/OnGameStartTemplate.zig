const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const GameContext = @import("IM").GameContext;
const ScriptType = @import("IM").ScriptType;
const ScriptResult = @import("IM").ScriptResult;
const GameContextOnGameStartScript = @This();

/// Function that gets executed once when the game starts, before the scenes' OnSceneStart scripts
/// return .Continue and it allows the event to be propegated to other layers/systems
/// return .Handled and it will stop at this layer
pub export fn Run(engine_context: *EngineContext, self: *const GameContext) callconv(.c) ScriptResult {
    _ = engine_context;
    _ = self;
    //your code goes here
    return .Continue;
}
//Note the following functions are for editor purposes and to not be changed by user or bad things can happen :)
pub export fn GetScriptType() callconv(.c) ScriptType {
    return ScriptType.GameContextGameStart;
}

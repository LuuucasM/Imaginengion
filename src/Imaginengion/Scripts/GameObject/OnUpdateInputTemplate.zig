const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const ScriptType = @import("IM").ScriptType;
const OnUpdateInputScript = @This();

/// Function that gets executed every frame after polling inputs and input events
/// if this function returns true it allows the event to be propegated to other layers/systems
/// if it returns false it will stop at this layer
pub export fn Run(engine_context: *EngineContext, self: *const Entity) callconv(.c) bool {
    _ValidateScript(OnUpdateInputScript);
    _ = engine_context;
    _ = self;
    //your code goes here
    return true;
}

//Note the following functions are for editor purposes and to not be changed by user or bad things can happen :)
pub export fn GetScriptType() callconv(.c) ScriptType {
    return ScriptType.EntityOnUpdate;
}

//This function helps validate that the script provided by the user
//will not break anything when trying to use
//It is intended to fail fast before it can even compile
const _ValidateScript = @import("IM")._ValidateScript;

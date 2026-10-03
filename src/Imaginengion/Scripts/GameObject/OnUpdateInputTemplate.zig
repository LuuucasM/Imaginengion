const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const ScriptType = @import("IM").ScriptType;
const ScriptResult = @import("IM").ScriptResult;
const EntityOnUpdateScript = @This();

/// Function that gets executed every frame after polling inputs and input events
/// return .Continue and it allows the event to be propegated to other layers/systems
/// return .Handled and it will stop at this layer
pub export fn Run(engine_context: *EngineContext, self: *const Entity) callconv(.c) ScriptResult {
    _ = engine_context;
    _ = self;
    //your code goes here
    return .Continue;
}
//Note the following functions are for editor purposes and to not be changed by user or bad things can happen :)
pub export fn GetScriptType() callconv(.c) ScriptType {
    return ScriptType.EntityOnUpdate;
}

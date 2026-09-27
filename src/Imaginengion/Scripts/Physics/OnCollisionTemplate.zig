const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const ScriptType = @import("IM").ScriptType;
const OnCollisionScript = @This();

/// Function that gets executed when this entity collides with another
/// if this function returns true it allows the event to be propegated to other layers/systems
/// if it returns false it will stop at this layer
pub export fn Run(engine_context: *EngineContext, self: *const Entity) callconv(.c) bool {
    _ = engine_context;
    _ = self;
    //your code goes here
    return true;
}
//Note the following functions are for editor purposes and to not be changed by user or bad things can happen :)
//TODO: there is no collision ScriptType yet, so this reports EntityOnUpdate (the type whose Run signature it matches)
pub export fn GetScriptType() callconv(.c) ScriptType {
    return ScriptType.EntityOnUpdate;
}

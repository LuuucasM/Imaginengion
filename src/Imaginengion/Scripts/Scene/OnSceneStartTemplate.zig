const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const SceneLayer = @import("IM").SceneLayer;
const ScriptType = @import("IM").ScriptType;
const ScriptResult = @import("IM").ScriptResult;
const SceneOnSceneStartScript = @This();

/// Function that gets executed when a scene is starting
/// return .Continue and it allows the event to be propegated to other layers/systems
/// return .Handled and it will stop at this layer
pub export fn Run(engine_context: *EngineContext, self: *const SceneLayer) callconv(.c) ScriptResult {
    _ = engine_context;
    _ = self;
    //your code goes here
    return .Continue;
}
//Note the following functions are for editor purposes and to not be changed by user or bad things can happen :)
pub export fn GetScriptType() callconv(.c) ScriptType {
    return ScriptType.SceneSceneStart;
}

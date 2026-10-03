const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const SceneLayer = @import("IM").SceneLayer;
const ScriptType = @import("IM").ScriptType;
const ScriptResult = @import("IM").ScriptResult;
const SceneOnPhysicsUpdateScript = @This();

/// Function that gets executed at the start of every physics step: at the physics' own fixed rate, not once a
/// frame. A scene's physics update scripts run before its entities' on each step, so this is the place for rules
/// of the scene that the physics should feel, e.g. a push on every body in it.
/// A force applied here pushes for this whole step and is let go of after it.
///     self: the scene this script is on
///     dt:   the length of the step in seconds, the same every step
/// return .Continue and the other physics update scripts run after it
/// return .Handled and it will stop at this script
pub export fn Run(engine_context: *EngineContext, self: *const SceneLayer, dt: f32) callconv(.c) ScriptResult {
    _ = engine_context;
    _ = self;
    _ = dt;
    //your code goes here
    return .Continue;
}
//Note the following functions are for editor purposes and to not be changed by user or bad things can happen :)
pub export fn GetScriptType() callconv(.c) ScriptType {
    return ScriptType.SceneOnPhysicsUpdate;
}

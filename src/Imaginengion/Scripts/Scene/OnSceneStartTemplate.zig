const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const SceneLayer = @import("IM").SceneLayer;
const ScriptType = @import("IM").ScriptType;
const OnSceneStartScript = @This();

/// Function that gets executed when a scene is starting
/// if this function returns true it allows the event to be propegated to other layers/systems
/// if it returns false it will stop at this layer
pub export fn Run(engine_context: *EngineContext, allocator: *const std.mem.Allocator, self: *const SceneLayer) callconv(.c) bool {
    _ = engine_context;
    _ = allocator;
    _ = self;
    //your code goes here
    return true;
}

pub export fn EditorRender() callconv(.c) void {}

//Note the following functions are for editor purposes and to not be changed by user or bad things can happen :)
pub export fn GetScriptType() callconv(.c) ScriptType {
    return ScriptType.OnSceneStart;
}

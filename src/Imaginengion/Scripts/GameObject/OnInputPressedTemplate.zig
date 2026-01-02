const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const ScriptType = @import("IM").ScriptType;
const InputPressedEvent = @import("IM").SystemEvent.InputPressedEvent;

const OnInputPressedScript = @This();

/// Function that gets executed when a key pressed event is triggered
/// if this function returns true it allows the event to be propegated to other SceneLayers
/// if it returns false it will stop at this layer
pub export fn Run(engine_context: *EngineContext, allocator: *const std.mem.Allocator, self: *const Entity, e: *const InputPressedEvent) callconv(.c) bool {
    _ValidateScript(OnInputPressedScript);

    _ = engine_context;
    _ = allocator;
    _ = self;
    _ = e;
    //your code goes here
    return true;
}

//Note the following functions are for editor purposes and to not be changed by user or bad things can happen :)
pub export fn GetScriptType() callconv(.c) ScriptType {
    return ScriptType.OnInputPressed;
}

const _ValidateScript = @import("IM")._ValidateScript;

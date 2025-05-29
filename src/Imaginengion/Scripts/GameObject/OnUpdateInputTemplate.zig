const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const ScriptType = @import("IM").ScriptType;
const OnUpdateInputScript = @This();

/// Function that gets executed every frame after polling inputs and input events
/// if this function returns true it allows the event to be propegated to other layers/systems
/// if it returns false it will stop at this layer
pub export fn Run(engine_context: *EngineContext, allocator: *const std.mem.Allocator, self: *const Entity) callconv(.C) bool {
    _ = engine_context;
    _ = allocator;
    _ = self;
    //your code goes here
    return true;
}

pub export fn EditorRender() callconv(.C) void {}

//Note the following functions are for editor purposes and to not be changed by user or bad things can happen :)
pub export fn GetScriptType() callconv(.C) ScriptType {
    return ScriptType.OnUpdateInput;
}

const std = @import("std");
const Entity = @import("IM").Entity;
const ScriptType = @import("IM").ScriptType;
const KeyPressedEvent = @import("IM").SystemEvent.KeyPressedEvent;

/// Function that gets executed when a key pressed event is triggered
/// if this function returns true it allows the event to be propegated to other layers/systems
/// if it returns false it will stop at this layer
pub export fn Run(allocator: *const std.mem.Allocator, self: *const Entity, e: *const KeyPressedEvent) bool {
    _ = e;
    _ = self;
    _ = allocator;
    //your code goes here
    return true;
}

pub export fn GetScriptType() ScriptType {
    return ScriptType.OnKeyPressed;
}

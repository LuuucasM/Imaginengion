const std = @import("std");
const Entity = @import("IM").Entity;
const ScriptType = @import("IM").ScriptType;
const KeyPressedEvent = @import("IM").SystemEvent.KeyPressedEvent;

/// Function that gets executed when a key pressed event is triggered
pub export fn Run(allocator: *std.mem.Allocator, self: *Entity, e: *KeyPressedEvent) anyerror!void {
    _ = e;
    _ = self;
    _ = allocator;
    //your code goes here
}

pub export fn GetScriptType() ScriptType {
    return ScriptType.OnKeyPressed;
}

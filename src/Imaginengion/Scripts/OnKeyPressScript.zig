const std = @import("std");
const Entity = @import("IM").Entity;
const ScriptType = @import("IM").ScriptType;

pub export fn Run(self: *Entity) void {
    _ = self;
    //your code goes here
}

pub export fn GetScriptType() ScriptType {
    return ScriptType.OnKeyPressed;
}

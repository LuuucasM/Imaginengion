const std = @import("std");
const ComponentsList = @import("../ScriptTypes.zig").ComponentsList;
const AnimationScript = @This();

mScript: std.DynLib,

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == AnimationScript) {
            break :blk i;
        }
    }
};

pub fn EditorRender(entity_script: AnimationScript) void {
    _ = entity_script;
    //your code goes here
}

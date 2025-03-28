const std = @import("std");
const ComponentsList = @import("../ScriptTypes.zig").ComponentsList;
const CollisionScript = @This();

mScript: std.DynLib,

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == CollisionScript) {
            break :blk i;
        }
    }
};

pub fn EditorRender(entity_script: CollisionScript) void {
    _ = entity_script;
    //your code goes here
}

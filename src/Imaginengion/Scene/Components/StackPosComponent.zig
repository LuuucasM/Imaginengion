const ComponentsList = @import("../Components.zig").ComponentsList;
const StackPosComponent = @This();

mPosition: usize,

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == StackPosComponent) {
            break :blk i;
        }
    }
};

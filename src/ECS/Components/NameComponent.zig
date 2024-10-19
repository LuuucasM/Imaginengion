const ComponentsList = @import("../Components.zig").ComponentsList;
const NameComponent = @This();

Name: [24]u8,

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == NameComponent) {
            break :blk i;
        }
    }
};

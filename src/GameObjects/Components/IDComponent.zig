const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const IDComponent = @This();

ID: u128 = std.math.maxInt(u128),

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == IDComponent) {
            break :blk i;
        }
    }
};

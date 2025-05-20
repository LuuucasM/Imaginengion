const ComponentsList = @import("../Components.zig").ComponentsList;
const StackPosComponent = @This();

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == StackPosComponent) {
            break :blk i;
        }
    }
};

mPosition: usize,

pub fn Deinit(_: *StackPosComponent) !void {}

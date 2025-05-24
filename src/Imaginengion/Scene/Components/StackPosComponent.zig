const std = @import("std");
const ComponentsList = @import("../SceneComponents.zig").ComponentsList;
const StackPosComponent = @This();

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == StackPosComponent) {
            break :blk i;
        }
    }
};

mPosition: usize = std.math.maxInt(usize),

pub fn Deinit(_: *StackPosComponent) !void {}

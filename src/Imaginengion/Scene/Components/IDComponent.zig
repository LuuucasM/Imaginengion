const std = @import("std");
const ComponentsList = @import("../SceneComponents.zig").ComponentsList;
const IDComponent = @This();

ID: u64 = std.math.maxInt(u64),

pub fn Deinit(_: *IDComponent) !void {}

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == IDComponent) {
            break :blk i;
        }
    }
};

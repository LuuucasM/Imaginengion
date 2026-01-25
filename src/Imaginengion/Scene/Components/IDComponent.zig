const std = @import("std");
const ComponentsList = @import("../SceneComponents.zig").ComponentsList;
const IDComponent = @This();
const EngineContext = @import("../../Core/EngineContext.zig");

ID: u64 = std.math.maxInt(u64),

pub const Name: []const u8 = "IDComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == IDComponent) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

pub fn Deinit(_: *IDComponent, _: *EngineContext) !void {}

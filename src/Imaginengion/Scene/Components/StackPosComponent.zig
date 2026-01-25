const std = @import("std");
const ComponentsList = @import("../SceneComponents.zig").ComponentsList;
const StackPosComponent = @This();
const EngineContext = @import("../../Core/EngineContext.zig");

pub const Name: []const u8 = "StackPosComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == StackPosComponent) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

mPosition: usize = std.math.maxInt(usize),

pub fn Deinit(_: *StackPosComponent, _: *EngineContext) !void {}

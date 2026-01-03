const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const IDComponent = @This();
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;
const EngineContext = @import("../../Core/EngineContext.zig");

pub const Category: ComponentCategory = .Unique;
pub const Editable: bool = false;

SceneID: u128 = std.math.maxInt(u128),

pub fn Deinit(_: *IDComponent, _: EngineContext) !void {}

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == IDComponent) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

pub fn GetName(_: IDComponent) []const u8 {
    return "IDComponent";
}

pub fn GetInd(_: IDComponent) u32 {
    return @intCast(Ind);
}

const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const Entity = @import("../../GameObjects/Entity.zig");
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;
const AILinkComponent = @This();

mAIEntity: Entity.Type = Entity.NullEntity,

pub fn Deinit(_: *AILinkComponent) !void {}

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == AILinkComponent) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

pub const Category: ComponentCategory = .Unique;

pub const Editable: bool = false;

const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const Entity = @import("../../GameObjects/Entity.zig");
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;
const EngineContext = @import("../../Core/EngineContext.zig");
const AISlotComponent = @This();

mAIEntity: Entity.Type = Entity.NullEntity,

pub fn Deinit(_: *AISlotComponent, _: *EngineContext) !void {}

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == AISlotComponent) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

pub fn GetInd(self: AISlotComponent) u32 {
    _ = self;
    return @intCast(Ind);
}

pub const Category: ComponentCategory = .Unique;

pub const Editable: bool = false;

pub fn GetName(_: AISlotComponent) []const u8 {
    return "AISlotComponent";
}

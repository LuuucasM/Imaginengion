const BuiltinComponentCount = @import("../../ECS/Components.zig").BuiltinComponentCount;
const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const EntitySceneComponent = @This();
const EngineContext = @import("../../Core/EngineContext.zig");
const SceneLayer = @import("../../Scene/SceneLayer.zig");

pub const Editable: bool = false;
pub const Name: []const u8 = "EntitySceneComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == EntitySceneComponent) {
            break :blk i + BuiltinComponentCount;
        }
    }
};

mScene: SceneLayer = undefined,

pub fn Deinit(_: *EntitySceneComponent, _: *EngineContext) !void {}

const BuiltinComponentCount = @import("../../ECS/Components.zig").BuiltinComponentCount;
const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const Entity = @import("../../GameObjects/Entity.zig");
const EngineContext = @import("../../Core/EngineContext.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const AISlotComponent = @This();

pub const Editable: bool = false;
pub const Name: []const u8 = "AISlotComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == AISlotComponent) {
            break :blk i + BuiltinComponentCount;
        }
    }
};

mAIEntity: Entity.Type = Entity.NullEntity,

pub fn Deinit(_: *AISlotComponent, _: *EngineContext) !void {}

pub fn EditorRender(_: *AISlotComponent, _: *EngineContext) !void {}

//nothing is saved yet
const Json = JsonUtils.JsonFields(AISlotComponent, .{});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

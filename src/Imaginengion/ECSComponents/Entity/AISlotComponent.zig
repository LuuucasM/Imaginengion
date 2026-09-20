const std = @import("std");
const Entity = @import("../../ECSObjects/Entity.zig");
const EngineContext = @import("../../Core/EngineContext.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const AISlotComponent = @This();

pub const Editable: bool = false;
pub const Name: []const u8 = "AISlotComponent";

mAIEntity: Entity.Type = Entity.NullEntity,

pub fn Deinit(_: *AISlotComponent, _: *EngineContext) void {}

pub fn EditorRender(_: *AISlotComponent, _: *EngineContext) !void {}

//nothing is saved yet
const Json = JsonUtils.JsonFields(AISlotComponent, .{});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

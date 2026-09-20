const std = @import("std");
const Player = @import("../../ECSObjects/Player.zig");
const EngineContext = @import("../../Core/EngineContext.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");

const PlayerSlotComponent = @This();

pub const Editable: bool = false;
pub const Name: []const u8 = "PlayerSlotComponent";

mPlayerEntity: Player = .uninit,

pub fn Deinit(_: *PlayerSlotComponent, _: *EngineContext) void {}

pub fn EditorRender(_: *PlayerSlotComponent, _: *EngineContext) !void {}

//nothing is saved yet
const Json = JsonUtils.JsonFields(PlayerSlotComponent, .{});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

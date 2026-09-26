const std = @import("std");
const EngineContext = @import("../../Core/EngineContext.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const MicComponent = @This();

pub const Editable: bool = false;
pub const Name: []const u8 = "MicComponent";

//the player's listener. empty until 3D audio: it will hold per-player listener settings and state, but never
//the output buffer the device thread reads from, since ECS storage can move under that thread's pointer

pub fn Deinit(_: *MicComponent, _: *EngineContext) void {}

//nothing is saved yet
const Json = JsonUtils.JsonFields(MicComponent, .{});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

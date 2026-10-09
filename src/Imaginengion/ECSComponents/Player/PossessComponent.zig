const Entity = @import("../../ECSObjects/Entity.zig");
const EngineContext = @import("../../Core/EngineContext.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const PossessComponent = @This();

pub const Name: []const u8 = "PossessComponent";

mPossessedEntity: Entity = .uninit,

pub fn Deinit(_: *PossessComponent, _: *EngineContext) void {}

//only that the player can possess is saved, what it possesses is decided at runtime
const Json = JsonUtils.JsonFields(PossessComponent, .{});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

const Entity = @import("../../ECSObjects/Entity.zig");
const Inspector = @import("../../UI/Inspector.zig");
const EngineContext = @import("../../Core/EngineContext.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const PossessComponent = @This();

pub const Name: []const u8 = "PossessComponent";

mPossessedEntity: Entity = .uninit,

/// Shown only: possessing goes through Player.Possess, which links both sides, and there is nothing in the editor's
/// own UI to drag an entity from yet
pub fn UIRender(self: *PossessComponent, ui: *Inspector.Builder) !void {
    try ui.EntityName(&self.mPossessedEntity, "Possessed");
}

pub fn Deinit(_: *PossessComponent, _: *EngineContext) void {}

//only that the player can possess is saved, what it possesses is decided at runtime
const Json = JsonUtils.JsonFields(PossessComponent, .{});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

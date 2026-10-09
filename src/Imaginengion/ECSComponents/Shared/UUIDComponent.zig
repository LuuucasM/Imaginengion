const std = @import("std");
const Inspector = @import("../../UI/Inspector.zig");
const UUIDComponent = @This();
const EngineContext = @import("../../Core/EngineContext.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");


pub const Editable: bool = true;
pub const Name: []const u8 = "UUIDComponent";

pub const empty: UUIDComponent = .{
    .ID = std.math.maxInt(u64),
};

ID: u64 = std.math.maxInt(u64),

pub fn Deinit(_: *UUIDComponent, _: *EngineContext) void {}

pub fn UIRender(self: *UUIDComponent, ui: *Inspector.Builder) !void {
    try ui.Readout(&self.ID, "UUID", ShowID);
}

fn ShowID(id: u64, buffer: []u8) []const u8 {
    return std.fmt.bufPrint(buffer, "{d}", .{id}) catch "?";
}

const Json = JsonUtils.JsonFields(UUIDComponent, .{ .UUID = "ID" });
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

/// Registers the loaded UUID with the manager of whatever object owns this component (entity, scene, ...)
pub fn PostParse(self: *UUIDComponent, engine_context: *EngineContext, owner: anytype) !void {
    try owner.mManager.GetManager(@TypeOf(owner)).AddUUID(engine_context.EngineAllocator(), self.ID, owner.mID);
}

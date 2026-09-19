const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const UUIDComponent = @This();
const EngineContext = @import("../../Core/EngineContext.zig");
const ImguiManager = @import("../../Imgui/Imgui.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");

//IMGUI
const imgui = @import("../../Core/CImports.zig").imgui;

pub const Editable: bool = true;
pub const Name: []const u8 = "UUIDComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == UUIDComponent) {
            break :blk i + 5; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

pub const empty: UUIDComponent = .{
    .ID = std.math.maxInt(u64),
};

ID: u64 = std.math.maxInt(u64),

pub fn Deinit(_: *UUIDComponent, _: *EngineContext) !void {}

pub fn EditorRender(self: *UUIDComponent, _: *EngineContext) !void {
    try ImguiManager.RenderUUID(&self.ID, "UUID");
}

const Json = JsonUtils.JsonFields(UUIDComponent, .{ .UUID = "ID" });
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

/// Registers the loaded UUID with the manager of whatever object owns this component (entity, scene, ...)
pub fn PostParse(self: *UUIDComponent, engine_context: *EngineContext, owner: anytype) !void {
    try owner.mManager.GetManager(@TypeOf(owner)).AddUUID(engine_context.EngineAllocator(), self.ID, owner.mID);
}

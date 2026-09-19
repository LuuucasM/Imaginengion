const BuiltinComponentCount = @import("../../ECS/Components.zig").BuiltinComponentCount;
const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const NameComponent = @This();
const EngineContext = @import("../../Core/EngineContext.zig");

const ImguiManager = @import("../../Imgui/Imgui.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");

pub const Editable: bool = true;
pub const Name: []const u8 = "NameComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == NameComponent) {
            break :blk i + BuiltinComponentCount;
        }
    }
};
pub const empty: NameComponent = .{
    .mName = .empty,
};

mName: std.ArrayList(u8) = .empty,

pub fn Deinit(self: *NameComponent, engine_context: *EngineContext) !void {
    self.mName.deinit(engine_context.EngineAllocator());
}

pub fn EditorRender(self: *NameComponent, engine_context: *EngineContext) !void {
    try ImguiManager.RenderTextInput(engine_context, &self.mName, "Text");
}

const Json = JsonUtils.JsonFields(NameComponent, .{ .Name = "mName" });
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

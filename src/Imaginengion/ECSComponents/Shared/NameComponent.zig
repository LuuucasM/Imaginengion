const std = @import("std");
const NameComponent = @This();
const EngineContext = @import("../../Core/EngineContext.zig");

const ImguiManager = @import("../../Imgui/Imgui.zig");
const Inspector = @import("../../UI/Inspector.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");

pub const Editable: bool = true;
pub const Name: []const u8 = "NameComponent";
pub const empty: NameComponent = .{
    .mName = .empty,
};

mName: std.ArrayList(u8) = .empty,

pub fn Deinit(self: *NameComponent, engine_context: *EngineContext) void {
    self.mName.deinit(engine_context.EngineAllocator());
}

pub fn Clone(self: *const NameComponent, engine_context: *EngineContext) !NameComponent {
    return .{ .mName = try self.mName.clone(engine_context.EngineAllocator()) };
}

pub fn EditorRender(self: *NameComponent, engine_context: *EngineContext) !void {
    try ImguiManager.RenderTextInput(engine_context, &self.mName, "Text");
}

pub fn UIRender(self: *NameComponent, ui: *Inspector.Builder) !void {
    try ui.Text(&self.mName, "Name", .{});
}

const Json = JsonUtils.JsonFields(NameComponent, .{ .Name = "mName" });
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

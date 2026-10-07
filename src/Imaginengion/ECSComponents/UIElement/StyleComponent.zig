const std = @import("std");
const imgui = @import("../../Core/CImports.zig").imgui;
const EngineContext = @import("../../Core/EngineContext.zig");
const ImguiManager = @import("../../Imgui/Imgui.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const Inspector = @import("../../UI/Inspector.zig");

const StyleComponent = @This();

pub const Editable: bool = true;
pub const Name: []const u8 = "StyleComponent";

/// On an entity's UI element (UIElementComponent): which style of the current theme the entity looks like, by name,
/// e.g. "Button". Every frame the style system writes the style's colors (for the state the entity is in: pressed,
/// hovered, focused, selected or none of those), border, corners and font into the entity's quad and text. While it has
/// a style, those are the style's: set them by hand and they are written over. See ThemeAsset.zig
mStyle: std.ArrayList(u8) = .empty,

pub fn Deinit(self: *StyleComponent, engine_context: *EngineContext) void {
    self.mStyle.deinit(engine_context.EngineAllocator());
}

pub fn Clone(self: *const StyleComponent, engine_context: *EngineContext) !StyleComponent {
    return .{ .mStyle = try self.mStyle.clone(engine_context.EngineAllocator()) };
}

/// A style component for the style called `name`
pub fn Init(engine_context: *EngineContext, name: []const u8) !StyleComponent {
    var style = StyleComponent{};
    try style.mStyle.appendSlice(engine_context.EngineAllocator(), name);
    return style;
}

pub fn UIRender(self: *StyleComponent, ui: *Inspector.Builder) !void {
    try ui.Text(&self.mStyle, "Style", .{});
}

pub fn EditorRender(self: *StyleComponent, engine_context: *EngineContext) !void {
    try ImguiManager.RenderTextInput(engine_context, &self.mStyle, "Style");
    if (imgui.igIsItemHovered(0)) imgui.igSetTooltip("The name of a style in the current theme (Editor > UI Theme...)");
}

const Json = JsonUtils.JsonFields(StyleComponent, .{
    .Style = "mStyle",
});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

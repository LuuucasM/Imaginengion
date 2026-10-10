const std = @import("std");
const EngineContext = @import("../../Core/EngineContext.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const Inspector = @import("../../UI/Inspector.zig");
const AssetHandle = @import("../../ECSObjects/AssetHandle.zig");

const StyleComponent = @This();

pub const Editable: bool = true;
pub const Name: []const u8 = "StyleComponent";

/// On an entity's UI element (UIElementComponent): which style the entity looks like, by name, e.g. "Button", out of
/// its theme file, or the editor's theme for none. Optional: an entity without one keeps whatever is set on it. Every frame the style system writes the style's colors (for the state the entity is in: pressed,
/// hovered, focused, selected or none of those), border, corners and font into the entity's quad and text. While it has
/// a style, those are the style's: set them by hand and they are written over. See ThemeAsset.zig
mStyle: std.ArrayList(u8) = .empty,
/// The theme file (.imtheme) the style is looked up in. uninit for the editor's theme
mTheme: AssetHandle = .uninit,
/// Taken once and then taken off: the style's colors, corners and font become the entity's own, which nothing writes
/// over after. For UI made in a game, which keeps what is set on it (see UIManager.StyleOnce). Never saved, it is gone
/// by the next frame
mOnce: bool = false,

pub fn Deinit(self: *StyleComponent, engine_context: *EngineContext) void {
    self.mStyle.deinit(engine_context.EngineAllocator());
    self.mTheme.ReleaseAsset();
}

pub fn Clone(self: *const StyleComponent, engine_context: *EngineContext) !StyleComponent {
    //the copy releases its theme itself, so it needs its own reference
    self.mTheme.RetainAsset();
    return .{ .mStyle = try self.mStyle.clone(engine_context.EngineAllocator()), .mTheme = self.mTheme, .mOnce = self.mOnce };
}

/// A style component for the style called `name`
pub fn Init(engine_context: *EngineContext, name: []const u8) !StyleComponent {
    var style = StyleComponent{};
    try style.mStyle.appendSlice(engine_context.EngineAllocator(), name);
    return style;
}

pub fn UIRender(self: *StyleComponent, ui: *Inspector.Builder) !void {
    try ui.Asset(&self.mTheme, "Theme", &.{".imtheme"}, .{});
    try ui.Text(&self.mStyle, "Style", .{});
}

const Json = JsonUtils.JsonFields(StyleComponent, .{
    .Theme = "mTheme",
    .Style = "mStyle",
});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

const std = @import("std");
const EngineContext = @import("../../Core/EngineContext.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const Layout = @import("../../UI/Layout.zig");
const Inspector = @import("../../UI/Inspector.zig");

const ScrollComponent = @This();

pub const Editable: bool = true;
pub const Name: []const u8 = "ScrollComponent";

/// On an entity's UI element (UIElementComponent): scrolls the entity's children when they run past it. The entity has to
/// be a layout container (LayoutComponent) with a size that doesn't come from its children (Fixed, Fill or Percent),
/// and is cut off at its edges by a MaskComponent with its shape (ShapeComponent), which it is given if it has none. The mouse wheel over it scrolls it,
/// and a scrollbar shows along each edge it overflows, which can be dragged (see UI/ScrollSystem.zig). How far it is
/// scrolled is the element's ScrollStateComponent
mScroll: Layout.Scroll = .Vertical,
/// How far one notch of the mouse wheel scrolls, in the tree's units (canvas units in an overlay)
mWheelStep: f32 = 40,

pub fn Deinit(_: *ScrollComponent, _: *EngineContext) void {}

pub fn UIRender(self: *ScrollComponent, ui: *Inspector.Builder) !void {
    try ui.Enum(Layout.Scroll, &self.mScroll, "Scroll", .{});
    try ui.Float(&self.mWheelStep, "Wheel Step", .{ .Speed = 0.5, .Min = 0, .Decimals = 1 });
}

const Json = JsonUtils.JsonFields(ScrollComponent, .{
    .Scroll = "mScroll",
    .WheelStep = "mWheelStep",
});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

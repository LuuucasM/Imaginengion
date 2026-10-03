const std = @import("std");
const imgui = @import("../../Core/CImports.zig").imgui;
const EngineContext = @import("../../Core/EngineContext.zig");
const ImguiManager = @import("../../Imgui/Imgui.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const Layout = @import("../../UI/Layout.zig");

const ScrollComponent = @This();

pub const Editable: bool = true;
pub const Name: []const u8 = "ScrollComponent";

/// On an entity's UI element (UIElementComponent): scrolls the entity's children when they run past it. The entity has to
/// be a layout container (LayoutComponent) with a size that doesn't come from its children (Fixed, Fill or Percent),
/// and is cut off at its edges by a ClipComponent, which it is given if it has none. The mouse wheel over it scrolls it,
/// and a scrollbar shows along each edge it overflows, which can be dragged (see UI/ScrollSystem.zig). How far it is
/// scrolled is the element's ScrollStateComponent
mScroll: Layout.Scroll = .Vertical,
/// How far one notch of the mouse wheel scrolls, in the tree's units (canvas units in an overlay)
mWheelStep: f32 = 40,

pub fn Deinit(_: *ScrollComponent, _: *EngineContext) void {}

pub fn EditorRender(self: *ScrollComponent, _: *EngineContext) !void {
    try ImguiManager.RenderEnum(Layout.Scroll, &self.mScroll, "Scroll");
    if (imgui.igIsItemHovered(0)) imgui.igSetTooltip("Needs a LayoutComponent, and a size that isn't Fit: Fixed, Fill or Percent");
    _ = try ImguiManager.RenderFloatDrag(&self.mWheelStep, "Wheel Step", 0.5, 0, std.math.floatMax(f32));
}

const Json = JsonUtils.JsonFields(ScrollComponent, .{
    .Scroll = "mScroll",
    .WheelStep = "mWheelStep",
});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

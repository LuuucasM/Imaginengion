const std = @import("std");
const EngineContext = @import("../../Core/EngineContext.zig");
const ImguiManager = @import("../../Imgui/Imgui.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const Layout = @import("../../UI/Layout.zig");

const LayoutComponent = @This();

pub const Editable: bool = true;
pub const Name: []const u8 = "LayoutComponent";

/// Makes an entity a layout container: it arranges its children that have a LayoutItemComponent, in a row or a
/// column. Children without one are left wherever their own transform puts them. Sizes are in the tree's units
/// (canvas units in an overlay scene). How the container itself is sized and placed is its LayoutItemComponent,
/// and a container without one is laid out as if it had the default one (fit to its children, in the flow)
mDirection: Layout.Direction = .Column,
mPadding: Layout.Padding = .{},
/// between each pair of children along the direction
mGap: f32 = 0,
mMainAlign: Layout.MainAlign = .Start,
mCrossAlign: Layout.CrossAlign = .Start,

pub fn Deinit(_: *LayoutComponent, _: *EngineContext) void {}

/// What the layout algorithm needs of it
pub fn ToContainer(self: LayoutComponent) Layout.Container {
    return .{
        .Direction = self.mDirection,
        .Padding = self.mPadding,
        .Gap = self.mGap,
        .MainAlign = self.mMainAlign,
        .CrossAlign = self.mCrossAlign,
    };
}

pub fn EditorRender(self: *LayoutComponent, _: *EngineContext) !void {
    try ImguiManager.RenderEnum(Layout.Direction, &self.mDirection, "Direction");
    try ImguiManager.RenderEnum(Layout.MainAlign, &self.mMainAlign, "Main Align");
    try ImguiManager.RenderEnum(Layout.CrossAlign, &self.mCrossAlign, "Cross Align");
    _ = try ImguiManager.RenderFloatDrag(&self.mGap, "Gap", 0.5, 0, std.math.floatMax(f32));

    try ImguiManager.RenderText("Padding");
    _ = try ImguiManager.RenderFloatDrag(&self.mPadding.Left, "Left", 0.5, 0, std.math.floatMax(f32));
    _ = try ImguiManager.RenderFloatDrag(&self.mPadding.Right, "Right", 0.5, 0, std.math.floatMax(f32));
    _ = try ImguiManager.RenderFloatDrag(&self.mPadding.Top, "Top", 0.5, 0, std.math.floatMax(f32));
    _ = try ImguiManager.RenderFloatDrag(&self.mPadding.Bottom, "Bottom", 0.5, 0, std.math.floatMax(f32));
}

const Json = JsonUtils.JsonFields(LayoutComponent, .{
    .Direction = "mDirection",
    .Padding = "mPadding",
    .Gap = "mGap",
    .MainAlign = "mMainAlign",
    .CrossAlign = "mCrossAlign",
});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

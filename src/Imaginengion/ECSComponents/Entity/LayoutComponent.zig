const std = @import("std");
const Inspector = @import("../../UI/Inspector.zig");
const EngineContext = @import("../../Core/EngineContext.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const Layout = @import("../../UI/Layout.zig");

const LayoutComponent = @This();

pub const Editable: bool = true;
pub const Name: []const u8 = "LayoutComponent";

/// Makes an entity a layout container: it arranges its children that have a LayoutItemComponent, in a row, a
/// column or a grid. Children without one are left wherever their own transform puts them. Sizes are in the tree's units
/// (canvas units in an overlay scene). How the container itself is sized and placed is its LayoutItemComponent,
/// and a container without one is laid out as if it had the default one (fit to its children, in the flow)
mDirection: Layout.Direction = .Column,
mPadding: Layout.Padding = .{},
/// between each pair of children along the direction. In a grid, between its columns and between its rows
mGap: f32 = 0,
mMainAlign: Layout.MainAlign = .Start,
mCrossAlign: Layout.CrossAlign = .Start,
/// only used by a grid
mColumns: Layout.Columns = .Auto,

pub fn Deinit(_: *LayoutComponent, _: *EngineContext) void {}

/// What the layout algorithm needs of it
pub fn ToContainer(self: LayoutComponent) Layout.Container {
    return .{
        .Direction = self.mDirection,
        .Padding = self.mPadding,
        .Gap = self.mGap,
        .MainAlign = self.mMainAlign,
        .CrossAlign = self.mCrossAlign,
        .Columns = self.mColumns,
    };
}

pub fn UIRender(self: *LayoutComponent, ui: *Inspector.Builder) !void {
    //a grid has columns, a row or column has alignments
    try ui.Enum(Layout.Direction, &self.mDirection, "Direction", .{ .Rebuilds = true });
    if (self.mDirection == .Grid) {
        try ui.Union(&self.mColumns, "Columns", .{ .Number = .{ .Speed = 0.1, .Min = 1, .Decimals = 0 } });
    } else {
        try ui.Enum(Layout.MainAlign, &self.mMainAlign, "Main Align", .{});
        try ui.Enum(Layout.CrossAlign, &self.mCrossAlign, "Cross Align", .{});
    }
    try ui.Float(&self.mGap, "Gap", .{ .Speed = 0.5, .Min = 0 });
    try ui.Struct(&self.mPadding, "Padding");
}

const Json = JsonUtils.JsonFields(LayoutComponent, .{
    .Direction = "mDirection",
    .Padding = "mPadding",
    .Gap = "mGap",
    .MainAlign = "mMainAlign",
    .CrossAlign = "mCrossAlign",
    .Columns = "mColumns",
});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

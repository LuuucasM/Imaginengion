const std = @import("std");
const imgui = @import("../../Core/CImports.zig").imgui;
const EngineContext = @import("../../Core/EngineContext.zig");
const ImguiManager = @import("../../Imgui/Imgui.zig");
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

pub fn EditorRender(self: *LayoutComponent, _: *EngineContext) !void {
    try ImguiManager.RenderEnum(Layout.Direction, &self.mDirection, "Direction");
    if (self.mDirection == .Grid) {
        RenderColumns(&self.mColumns);
    } else {
        //a grid's cells start at its top left
        try ImguiManager.RenderEnum(Layout.MainAlign, &self.mMainAlign, "Main Align");
        try ImguiManager.RenderEnum(Layout.CrossAlign, &self.mCrossAlign, "Cross Align");
    }
    _ = try ImguiManager.RenderFloatDrag(&self.mGap, "Gap", 0.5, 0, std.math.floatMax(f32));

    try ImguiManager.RenderText("Padding");
    _ = try ImguiManager.RenderFloatDrag(&self.mPadding.Left, "Left", 0.5, 0, std.math.floatMax(f32));
    _ = try ImguiManager.RenderFloatDrag(&self.mPadding.Right, "Right", 0.5, 0, std.math.floatMax(f32));
    _ = try ImguiManager.RenderFloatDrag(&self.mPadding.Top, "Top", 0.5, 0, std.math.floatMax(f32));
    _ = try ImguiManager.RenderFloatDrag(&self.mPadding.Bottom, "Bottom", 0.5, 0, std.math.floatMax(f32));
}

/// As many as fit, or a set number
fn RenderColumns(columns: *Layout.Columns) void {
    const is_auto = columns.* == .Auto;
    if (imgui.igBeginCombo("Columns", if (is_auto) "As many as fit" else "Set number", 0)) {
        defer imgui.igEndCombo();
        if (imgui.igSelectable_Bool("As many as fit", is_auto, 0, .{ .x = 0, .y = 0 })) columns.* = .Auto;
        if (imgui.igSelectable_Bool("Set number", !is_auto, 0, .{ .x = 0, .y = 0 }) and is_auto) columns.* = .{ .Count = 3 };
    }
    switch (columns.*) {
        .Auto => {
            //it takes its width from its parent: fitting its children it has none, and is one row
            if (imgui.igIsItemHovered(0)) imgui.igSetTooltip("Needs a width to fit the cells in: Fill, Percent or Fixed. Fit makes one row");
        },
        .Count => |*count| {
            var value: c_int = @intCast(count.*);
            if (imgui.igDragInt("Column Count", &value, 0.1, 1, 1000, "%d", 0)) count.* = @intCast(@max(value, 1));
        },
    }
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

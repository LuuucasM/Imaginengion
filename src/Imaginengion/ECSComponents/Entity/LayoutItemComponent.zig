const std = @import("std");
const Inspector = @import("../../UI/Inspector.zig");
const Vec2 = @import("../../Math/MathTypes.zig").Vec2;
const EngineContext = @import("../../Core/EngineContext.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const Layout = @import("../../UI/Layout.zig");

const LayoutItemComponent = @This();

pub const Editable: bool = true;
pub const Name: []const u8 = "LayoutItemComponent";

/// Makes an entity something layout sizes and places: its parent's LayoutComponent stacks it (Flow) or pins it
/// to a point of the parent (Anchored). Without a parent container it is the root of a layout tree, sized and
/// anchored against the screen in an overlay scene. Layout owns a flow item's translation; rotation and scale
/// stay the transform's own. Sizes are in the tree's units (canvas units in an overlay scene).
mWidth: Layout.Sizing = .Fit,
mHeight: Layout.Sizing = .Fit,
mPlacement: Layout.Placement = .Flow,
/// takes no room at all, and neither does anything under it
mCollapsed: bool = false,

/// The size layout last gave it. Worked out, never saved or edited: shown in the editor to see what layout did
mComputedSize: Vec2(f32) = .{ .x = 0, .y = 0 },
/// A leaf's text as layout last measured it, so a tree laid out again only measures the texts that changed. Worked
/// out, never saved or edited. Null until it is measured, or when it has no text to measure
mMeasuredText: ?MeasuredText = null,

/// The room a leaf's text takes on one line (or several, where it has line breaks), and the middle of that room
/// relative to where the text is placed
pub const MeasuredText = struct {
    Size: Vec2(f32),
    Center: Vec2(f32),
};

pub fn Deinit(_: *LayoutItemComponent, _: *EngineContext, _: std.mem.Allocator) void {}

/// What the layout algorithm needs of it, as a node with no container, content or links yet: the layout pass adds
/// those from the entity's other components and its place in the tree
pub fn ToNode(self: LayoutItemComponent) Layout.Node {
    return .{
        .Width = self.mWidth,
        .Height = self.mHeight,
        .Placement = self.mPlacement,
        .Collapsed = self.mCollapsed,
    };
}

pub fn UIRender(self: *LayoutItemComponent, ui: *Inspector.Builder) !void {
    try ui.Union(&self.mWidth, "Width", .{ .Number = .{ .Speed = 0.5, .Min = 0 } });
    try ui.Union(&self.mHeight, "Height", .{ .Number = .{ .Speed = 0.5, .Min = 0 } });
    try ui.Union(&self.mPlacement, "Placement", .{});
    try ui.Bool(&self.mCollapsed, "Collapsed", .{});
    try ui.Readout(&self.mComputedSize, "Computed Size", ShowSize);
}

fn ShowSize(size: Vec2(f32), buffer: []u8) []const u8 {
    return std.fmt.bufPrint(buffer, "{d:.2} x {d:.2}", .{ size.x, size.y }) catch "?";
}

//the computed size and measured text are left out: they are worked out again when the tree is laid out
const Json = JsonUtils.JsonFields(LayoutItemComponent, .{
    .Width = "mWidth",
    .Height = "mHeight",
    .Placement = "mPlacement",
    .Collapsed = "mCollapsed",
});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

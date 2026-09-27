const std = @import("std");
const imgui = @import("../../Core/CImports.zig").imgui;
const Vec2 = @import("../../Math/MathTypes.zig").Vec2;
const EngineContext = @import("../../Core/EngineContext.zig");
const ImguiManager = @import("../../Imgui/Imgui.zig");
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

pub fn Deinit(_: *LayoutItemComponent, _: *EngineContext) void {}

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

pub fn EditorRender(self: *LayoutItemComponent, _: *EngineContext) !void {
    RenderSizing("Width", &self.mWidth);
    RenderSizing("Height", &self.mHeight);

    imgui.igSeparator();
    RenderPlacement(&self.mPlacement);

    imgui.igSeparator();
    try ImguiManager.RenderBool(&self.mCollapsed, "Collapsed");
    imgui.igText("Computed size: %.2f x %.2f", self.mComputedSize.x, self.mComputedSize.y);
}

/// A sizing's kind, then its number for the kinds that have one
fn RenderSizing(comptime label: [:0]const u8, sizing: *Layout.Sizing) void {
    const Kind = std.meta.Tag(Layout.Sizing);
    const kinds = comptime std.meta.fieldNames(Kind);

    if (imgui.igBeginCombo(label.ptr, @tagName(sizing.*).ptr, 0)) {
        defer imgui.igEndCombo();
        inline for (kinds) |kind_name| {
            const kind = @field(Kind, kind_name);
            const is_selected = std.meta.activeTag(sizing.*) == kind;
            if (imgui.igSelectable_Bool(kind_name.ptr, is_selected, 0, .{ .x = 0, .y = 0 }) and !is_selected) {
                //a number to start from that does something visible: full size, an equal share, all of the parent
                sizing.* = switch (kind) {
                    .Fixed => .{ .Fixed = 100 },
                    .Fit => .Fit,
                    .Fill => .{ .Fill = 1 },
                    .Percent => .{ .Percent = 1 },
                };
            }
            if (is_selected) imgui.igSetItemDefaultFocus();
        }
    }

    switch (sizing.*) {
        .Fixed => |*size| _ = imgui.igDragFloat(label ++ " Size", size, 0.5, 0, std.math.floatMax(f32), "%.2f", 0),
        .Fill => |*weight| _ = imgui.igDragFloat(label ++ " Weight", weight, 0.05, 0, std.math.floatMax(f32), "%.2f", 0),
        .Percent => |*fraction| _ = imgui.igDragFloat(label ++ " Fraction", fraction, 0.005, 0, 1, "%.3f", 0),
        .Fit => {},
    }
}

fn RenderPlacement(placement: *Layout.Placement) void {
    const is_anchored = placement.* == .Anchored;
    if (imgui.igBeginCombo("Placement", @tagName(placement.*).ptr, 0)) {
        defer imgui.igEndCombo();
        if (imgui.igSelectable_Bool("Flow", !is_anchored, 0, .{ .x = 0, .y = 0 })) placement.* = .Flow;
        //anchored starts in the middle of the parent, where a flow item usually was anyway
        if (imgui.igSelectable_Bool("Anchored", is_anchored, 0, .{ .x = 0, .y = 0 }) and !is_anchored) placement.* = .{ .Anchored = .{} };
    }

    const anchoring = switch (placement.*) {
        .Anchored => |*anchoring| anchoring,
        .Flow => return,
    };

    //pinning a corner of the item to the same corner of the parent is the common case, so each preset sets the
    //anchor and pivot together
    imgui.igTextUnformatted("Pin to", null);
    const rows = [_]f32{ 1, 0, -1 };
    const columns = [_]f32{ -1, 0, 1 };
    const names = [_][:0]const u8{ "TL", "T", "TR", "L", "C", "R", "BL", "B", "BR" };
    for (rows, 0..) |y, row| {
        for (columns, 0..) |x, column| {
            if (column > 0) imgui.igSameLine(0, -1);
            if (imgui.igButton(names[row * 3 + column].ptr, .{ .x = 28, .y = 0 })) {
                anchoring.Anchor = .{ .x = x, .y = y };
                anchoring.Pivot = .{ .x = x, .y = y };
            }
        }
    }

    _ = imgui.igDragFloat2("Anchor", @ptrCast(&anchoring.Anchor), 0.01, -1, 1, "%.2f", 0);
    _ = imgui.igDragFloat2("Pivot", @ptrCast(&anchoring.Pivot), 0.01, -1, 1, "%.2f", 0);
    _ = imgui.igDragFloat2("Offset", @ptrCast(&anchoring.Offset), 0.5, -std.math.floatMax(f32), std.math.floatMax(f32), "%.2f", 0);
}

//the computed size is left out: it is worked out again every time the tree is laid out
const Json = JsonUtils.JsonFields(LayoutItemComponent, .{
    .Width = "mWidth",
    .Height = "mHeight",
    .Placement = "mPlacement",
    .Collapsed = "mCollapsed",
});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

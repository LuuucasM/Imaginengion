const imgui = @import("../../Core/CImports.zig").imgui;
const std = @import("std");
const EngineContext = @import("../../Core/EngineContext.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const Layout = @import("../../UI/Layout.zig");

const PopupComponent = @This();

pub const Editable: bool = true;
pub const Name: []const u8 = "PopupComponent";

/// Makes the entity the root of a popup: a menu or list that is hidden until something opens it (see
/// UI/PopupSystem.zig), then shown against what opened it. Opened and closed through its LayoutItemComponent's
/// Collapsed, so it needs one; the popup system adds a plain one if it has none.
/// How it sits against what opened it: Anchor is the point of the opener's rectangle (-1 to 1 across it, like
/// layout's), Pivot the point of the popup put there. Opened at a point instead (a right-click menu), only Pivot and
/// Offset count. The default hangs it below the opener, left edges lined up, which is a dropdown list
mPlacement: Layout.Anchoring = .{
    .Anchor = .{ .x = -1, .y = -1 },
    .Pivot = .{ .x = -1, .y = 1 },
},

pub fn Deinit(_: *PopupComponent, _: *EngineContext) void {}

pub fn EditorRender(self: *PopupComponent, _: *EngineContext) !void {
    //the usual ways a popup hangs off its opener, each setting the anchor and pivot together
    const Preset = struct { Name: [:0]const u8, Anchor: [2]f32, Pivot: [2]f32 };
    const presets = [_]Preset{
        //a dropdown list, a menu bar's menu, or a right-click menu at the pointer
        .{ .Name = "Below", .Anchor = .{ -1, -1 }, .Pivot = .{ -1, 1 } },
        //a submenu beside its row
        .{ .Name = "Right", .Anchor = .{ 1, 1 }, .Pivot = .{ -1, 1 } },
        .{ .Name = "Above", .Anchor = .{ -1, 1 }, .Pivot = .{ -1, -1 } },
    };
    imgui.igTextUnformatted("Open", null);
    for (presets) |preset| {
        imgui.igSameLine(0, -1);
        if (imgui.igButton(preset.Name.ptr, .{ .x = 0, .y = 0 })) {
            self.mPlacement.Anchor = .{ .x = preset.Anchor[0], .y = preset.Anchor[1] };
            self.mPlacement.Pivot = .{ .x = preset.Pivot[0], .y = preset.Pivot[1] };
        }
    }

    _ = imgui.igDragFloat2("Anchor", @ptrCast(&self.mPlacement.Anchor), 0.01, -1, 1, "%.2f", 0);
    _ = imgui.igDragFloat2("Pivot", @ptrCast(&self.mPlacement.Pivot), 0.01, -1, 1, "%.2f", 0);
    _ = imgui.igDragFloat2("Offset", @ptrCast(&self.mPlacement.Offset), 0.5, -std.math.floatMax(f32), std.math.floatMax(f32), "%.2f", 0);
}

const Json = JsonUtils.JsonFields(PopupComponent, .{
    .Placement = "mPlacement",
});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

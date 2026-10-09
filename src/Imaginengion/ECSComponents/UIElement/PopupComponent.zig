const std = @import("std");
const EngineContext = @import("../../Core/EngineContext.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const Layout = @import("../../UI/Layout.zig");
const Inspector = @import("../../UI/Inspector.zig");

const PopupComponent = @This();

pub const Editable: bool = true;
pub const Name: []const u8 = "PopupComponent";

/// On an entity's UI element (UIElementComponent): makes the entity the root of a popup, a menu or list that is hidden
/// until something opens it (see UI/PopupSystem.zig), then shown against what opened it. Opened and closed through the
/// entity's LayoutItemComponent's Collapsed, so it needs one; the popup system adds a plain one if it has none.
/// How it sits against what opened it: Anchor is the point of the opener's rectangle (-1 to 1 across it, like
/// layout's), Pivot the point of the popup put there. Opened at a point instead (a right-click menu), only Pivot and
/// Offset count. The default hangs it below the opener, left edges lined up, which is a dropdown list
mPlacement: Layout.Anchoring = .{
    .Anchor = .{ .x = -1, .y = -1 },
    .Pivot = .{ .x = -1, .y = 1 },
},

pub fn Deinit(_: *PopupComponent, _: *EngineContext) void {}

/// The usual ways a popup hangs off its opener, each setting the anchor and pivot together. Shown as a dropdown that
/// says Custom when the placement is none of them
const PlacementPreset = struct { Name: []const u8, Anchor: [2]f32, Pivot: [2]f32 };
const PRESETS = [_]PlacementPreset{
    //a dropdown list, a menu bar's menu, or a right-click menu at the pointer
    .{ .Name = "Below", .Anchor = .{ -1, -1 }, .Pivot = .{ -1, 1 } },
    //a submenu beside its row
    .{ .Name = "Right", .Anchor = .{ 1, 1 }, .Pivot = .{ -1, 1 } },
    .{ .Name = "Above", .Anchor = .{ -1, 1 }, .Pivot = .{ -1, -1 } },
};
const PRESET_NAMES = blk: {
    var names: [PRESETS.len + 1][]const u8 = undefined;
    for (PRESETS, 0..) |preset, i| names[i] = preset.Name;
    names[PRESETS.len] = "Custom";
    break :blk names;
};

/// The placement as a preset: which one it matches (Custom if none), and picking one sets its anchor and pivot
const PRESET_ACCESS = Inspector.Access{
    .Read = struct {
        fn Read(field: *anyopaque) Inspector.Value {
            const placement: *Layout.Anchoring = @ptrCast(@alignCast(field));
            for (PRESETS, 0..) |preset, i| {
                if (placement.Anchor.x == preset.Anchor[0] and placement.Anchor.y == preset.Anchor[1] and
                    placement.Pivot.x == preset.Pivot[0] and placement.Pivot.y == preset.Pivot[1]) return .{ .Choice = i };
            }
            return .{ .Choice = PRESETS.len };
        }
    }.Read,
    .Write = struct {
        fn Write(_: *EngineContext, field: *anyopaque, written: Inspector.Value) anyerror!void {
            //Custom isn't a placement of its own: it is what any other anchor and pivot show as
            if (written.Choice >= PRESETS.len) return;
            const placement: *Layout.Anchoring = @ptrCast(@alignCast(field));
            const preset = PRESETS[written.Choice];
            placement.Anchor = .{ .x = preset.Anchor[0], .y = preset.Anchor[1] };
            placement.Pivot = .{ .x = preset.Pivot[0], .y = preset.Pivot[1] };
        }
    }.Write,
};

pub fn UIRender(self: *PopupComponent, ui: *Inspector.Builder) !void {
    try ui.Choice(&self.mPlacement, "Open", &PRESET_NAMES, &PRESET_ACCESS, .{});
    try ui.Vec2Field(&self.mPlacement.Anchor, "Anchor", .{ .Speed = 0.01, .Min = -1, .Max = 1, .Decimals = 2 });
    try ui.Vec2Field(&self.mPlacement.Pivot, "Pivot", .{ .Speed = 0.01, .Min = -1, .Max = 1, .Decimals = 2 });
    try ui.Vec2Field(&self.mPlacement.Offset, "Offset", .{ .Speed = 0.5, .Decimals = 2 });
}

const Json = JsonUtils.JsonFields(PopupComponent, .{
    .Placement = "mPlacement",
});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

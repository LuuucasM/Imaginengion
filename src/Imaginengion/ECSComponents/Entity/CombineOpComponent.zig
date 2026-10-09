const std = @import("std");
const Inspector = @import("../../UI/Inspector.zig");
const EngineContext = @import("../../Core/EngineContext.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const ImguiManager = @import("../../Imgui/Imgui.zig");

const CombineOpComponent = @This();

pub const Editable: bool = true;
pub const Name: []const u8 = "CombineOpComponent";

/// How a part of a merge (MergeComponent) joins the rest of it. A part without one is a Union
mOp: Op = .Union,
//how far a smooth join reaches, in the same units as the shapes' sizes, growing with the part's scale like corner
//radii do. Where the two meet, the surface moves by at most this much, and the blending starts where they are 4 times
//this apart. 0 is a sharp join
mSmoothness: f32 = 0,

pub const Op = enum(u32) {
    /// adds its shape
    Union,
    /// cuts its shape out
    Subtract,
    /// keeps only what is inside its shape too
    Intersect,
};

pub fn Deinit(_: *CombineOpComponent, _: *EngineContext) void {}

pub fn UIRender(self: *CombineOpComponent, ui: *Inspector.Builder) !void {
    try ui.Enum(Op, &self.mOp, "Op", .{});
    try ui.Float(&self.mSmoothness, "Smoothness", .{ .Speed = 0.01, .Min = 0 });
}

pub fn EditorRender(self: *CombineOpComponent, _: *EngineContext) !void {
    try ImguiManager.RenderEnum(Op, &self.mOp, "Op");
    _ = try ImguiManager.RenderFloatDrag(&self.mSmoothness, "Smoothness", 0.01, 0, std.math.floatMax(f32));
}

const Json = JsonUtils.JsonFields(CombineOpComponent, .{
    .Op = "mOp",
    .Smoothness = "mSmoothness",
});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

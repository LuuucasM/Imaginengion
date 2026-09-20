const BuiltinComponentCount = @import("../../ECS/Components.zig").BuiltinComponentCount;
const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const EngineContext = @import("../../Core/EngineContext.zig");
const MathTypes = @import("../../Math/MathTypes.zig");
const MathUtils = @import("../../Math/MathUtils.zig");
const Mat4 = MathTypes.Mat4;
const Vec4 = MathTypes.Vec4;

const ViewpointComponent = @This();

const ImguiManager = @import("../../Imgui/Imgui.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");

pub const Editable = true;
pub const Name: []const u8 = "LensComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == ViewpointComponent) {
            break :blk i + BuiltinComponentCount;
        }
    }
};

//viewport stuff
mViewportWidth: usize = 1600,
mViewportHeight: usize = 900,
mAspectRatio: f32 = 0.0,

mProjection: Mat4(f32) = MathUtils.Mat4Identity(f32),

mIsFixedAspectRatio: bool = false,
mPerspectiveFOVRad: f32 = MathUtils.DegreesToRadians(60.0),
mPerspectiveNear: f32 = 0.01,
mPerspectiveFar: f32 = 1000.0,
mAreaRect: Vec4(f32) = .{ .x = 0.0, .y = 0.0, .z = 1.0, .w = 1.0 },

pub fn Deinit(_: *ViewpointComponent, _: *EngineContext) void {}

pub fn SetPerspective(self: *ViewpointComponent, fov_radians: f32, near_clip: f32, far_clip: f32) void {
    self.mPerspectiveFOVRad = fov_radians;
    self.mPerspectiveNear = near_clip;
    self.mPerspectiveFar = far_clip;
    self.RecalculateProjection();
}

pub fn SetAreaRect(self: *ViewpointComponent, new_area: Vec4(f32)) void {
    self.mAreaRect = new_area;
}

pub fn SetViewportSize(self: *ViewpointComponent, width: usize, height: usize) void {
    if (width == self.mViewportWidth and height == self.mViewportHeight) return;
    self.mViewportWidth = width;
    self.mViewportHeight = height;
    if (height > 0) {
        self.mAspectRatio = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height));
    } else {
        self.mAspectRatio = 0.0;
    }
    self.RecalculateProjection();
}

fn RecalculateProjection(self: *ViewpointComponent) void {
    self.mProjection = MathUtils.PerspectiveRHNO(self.mPerspectiveFOVRad, self.mAspectRatio, self.mPerspectiveNear, self.mPerspectiveFar);
}

pub fn EditorRender(self: *ViewpointComponent, _: *EngineContext) !void {

    //aspect ratio
    try ImguiManager.RenderBool(&self.mIsFixedAspectRatio, "Is Fixed Aspect Ratio?");

    //print the size/far/near variables depending on projection type
    var perspective_degrees = MathUtils.RadiansToDegrees(self.mPerspectiveFOVRad);
    if (try ImguiManager.RenderFloatDrag(&perspective_degrees, "FOV", 1.0, 0, 180.0)) {
        self.mPerspectiveFOVRad = MathUtils.DegreesToRadians(perspective_degrees);
        self.RecalculateProjection();
    }

    if (try ImguiManager.RenderFloatDrag(&self.mPerspectiveNear, "Perspective Near", 1.0, 0.0, 1.0)) {
        self.RecalculateProjection();
    }

    if (try ImguiManager.RenderFloatDrag(&self.mPerspectiveFar, "Perspective Far", 1.0, 2.0, 0.0)) {
        self.RecalculateProjection();
    }

    try ImguiManager.RenderFloat4Drag(&self.mAreaRect, "Area Rect", 0.01, 0, 1.0);
}

const Json = JsonUtils.JsonFields(ViewpointComponent, .{
    .IsFixedAspectRatio = "mIsFixedAspectRatio",
    .PerspectiveFOVRad = "mPerspectiveFOVRad",
    .PerspectiveNear = "mPerspectiveNear",
    .PerspectiveFar = "mPerspectiveFar",
    .AreaRect = "mAreaRect",
});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

pub fn PostParse(self: *ViewpointComponent, _: *EngineContext, _: anytype) !void {
    self.RecalculateProjection();
}

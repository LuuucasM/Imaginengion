const std = @import("std");
const Inspector = @import("../../UI/Inspector.zig");
const EngineContext = @import("../../Core/EngineContext.zig");
const MathTypes = @import("../../Math/MathTypes.zig");
const MathUtils = @import("../../Math/MathUtils.zig");
const Mat4 = MathTypes.Mat4;
const Vec4 = MathTypes.Vec4;
const CameraRay = @import("../../Math/CameraRay.zig");

const ViewpointComponent = @This();

const ImguiManager = @import("../../Imgui/Imgui.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");

pub const Editable = true;
pub const Name: []const u8 = "LensComponent";

const DEFAULT_WIDTH: usize = 1600;
const DEFAULT_HEIGHT: usize = 900;
const DEFAULT_ASPECT: f32 = @as(f32, @floatFromInt(DEFAULT_WIDTH)) / @as(f32, @floatFromInt(DEFAULT_HEIGHT));
const DEFAULT_FOV_RAD: f32 = MathUtils.DegreesToRadians(@as(f32, 60.0));
const DEFAULT_NEAR: f32 = 0.01;
const DEFAULT_FAR: f32 = 1000.0;

//viewport stuff
//the defaults have to agree with each other: SetViewportSize returns early when the size is
//unchanged, so a first call with exactly the default size would otherwise leave a zero aspect
//ratio and an identity projection behind
mViewportWidth: usize = DEFAULT_WIDTH,
mViewportHeight: usize = DEFAULT_HEIGHT,
mAspectRatio: f32 = DEFAULT_ASPECT,

mProjection: Mat4(f32) = MathUtils.PerspectiveRHNO(DEFAULT_FOV_RAD, DEFAULT_ASPECT, DEFAULT_NEAR, DEFAULT_FAR),

mIsFixedAspectRatio: bool = false,
mPerspectiveFOVRad: f32 = DEFAULT_FOV_RAD,
mPerspectiveNear: f32 = DEFAULT_NEAR,
mPerspectiveFar: f32 = DEFAULT_FAR,
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

/// The params that turn a pixel of this viewpoint's render target into a view space ray. Both
/// the shaders and CPU picking go through these, so what gets clicked is what got drawn.
pub fn GetRayParams(self: ViewpointComponent) CameraRay.RayParams {
    return CameraRay.ComputeRayParams(self.mPerspectiveFOVRad, @floatFromInt(self.mViewportWidth), @floatFromInt(self.mViewportHeight));
}

fn RecalculateProjection(self: *ViewpointComponent) void {
    self.mProjection = MathUtils.PerspectiveRHNO(self.mPerspectiveFOVRad, self.mAspectRatio, self.mPerspectiveNear, self.mPerspectiveFar);
}

pub fn UIRender(self: *ViewpointComponent, ui: *Inspector.Builder) !void {
    try ui.Bool(&self.mIsFixedAspectRatio, "Fixed Aspect Ratio", .{});
    try ui.Float(&self.mPerspectiveFOVRad, "FOV", .{ .Speed = 1, .Min = 1, .Max = 179, .Decimals = 1, .Convert = DEGREES, .OnChange = Reproject });
    try ui.Float(&self.mPerspectiveNear, "Near", .{ .Speed = 0.01, .Min = 0, .OnChange = Reproject });
    try ui.Float(&self.mPerspectiveFar, "Far", .{ .Speed = 1, .Min = 0, .OnChange = Reproject });
    //the part of the target it is drawn into, 0 to 1 across it: x, y, width, height
    try ui.Vec4Field(&self.mAreaRect, "Area", .{ .Speed = 0.01, .Min = 0, .Max = 1 });
}

/// The FOV is kept in radians and shown in degrees
const DEGREES = Inspector.Conversion{
    .ToShown = struct {
        fn ToShown(radians: f64) f64 {
            return std.math.radiansToDegrees(radians);
        }
    }.ToShown,
    .FromShown = struct {
        fn FromShown(degrees: f64) f64 {
            return std.math.degreesToRadians(degrees);
        }
    }.FromShown,
};

/// After a lens setting is edited: the projection worked out again from it
fn Reproject(component: *anyopaque) void {
    const self: *ViewpointComponent = @ptrCast(@alignCast(component));
    self.RecalculateProjection();
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

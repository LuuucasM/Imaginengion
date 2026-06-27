const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const EngineContext = @import("../../Core/EngineContext.zig");
const MathTypes = @import("../../Math/MathTypes.zig");
const MathUtils = @import("../../Math/MathUtils.zig");
const Mat4 = MathTypes.Mat4;
const Vec4 = MathTypes.Vec4;

const ViewpointComponent = @This();

const ImguiManager = @import("../../Imgui/Imgui.zig");

pub const Editable = true;
pub const Name: []const u8 = "LensComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == ViewpointComponent) {
            break :blk i + 5; // add 2 because 0 is parent component and 1 is child component provided by the ECS
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

pub fn Deinit(_: *ViewpointComponent, _: *EngineContext) !void {}

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
    ImguiManager.RenderBool(&self.mIsFixedAspectRatio, "Is Fixed Aspect Ratio?");

    //print the size/far/near variables depending on projection type
    var perspective_degrees = MathUtils.RadiansToDegrees(self.mPerspectiveFOVRad);
    if (ImguiManager.RenderFloatDrag(&perspective_degrees, "FOV", 1.0, 0, 180.0)) {
        self.mPerspectiveFOVRad = MathUtils.DegreesToRadians(perspective_degrees);
        self.RecalculateProjection();
    }

    if (ImguiManager.RenderFloatDrag(&self.mPerspectiveNear, "Perspective Near", 1.0, 0.0, 1.0)) {
        self.RecalculateProjection();
    }

    if (ImguiManager.RenderFloatDrag(&self.mPerspectiveFar, "Perspective Far", 1.0, 2.0, 0.0)) {
        self.RecalculateProjection();
    }

    ImguiManager.RenderFloat4Drag(&self.mAreaRect, "Area Rect", 0.01, 0, 1.0);
}

pub fn jsonStringify(self: *const ViewpointComponent, jw: anytype) !void {
    try jw.beginObject();

    try jw.objectField("IsFixedAspectRatio");
    try jw.write(self.mIsFixedAspectRatio);

    try jw.objectField("PerspectiveFOVRad");
    try jw.write(self.mPerspectiveFOVRad);

    try jw.objectField("PerspectiveNear");
    try jw.write(self.mPerspectiveNear);

    try jw.objectField("PerspectiveFar");
    try jw.write(self.mPerspectiveFar);

    try jw.objectField("AreaRect");
    try jw.write(self.mAreaRect);

    try jw.endObject();
}

pub fn jsonParse(frame_allocator: std.mem.Allocator, reader: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(reader.*))!ViewpointComponent {
    if (.object_begin != try reader.next()) return error.UnexpectedToken;

    var result: ViewpointComponent = .{};

    while (true) {
        const token = try reader.next();

        const field_name = switch (token) {
            .object_end => break,
            .string => |v| v,
            else => return error.UnexpectedToken,
        };

        if (std.mem.eql(u8, field_name, "IsFixedAspectRatio")) {
            result.mIsFixedAspectRatio = try std.json.innerParse(bool, frame_allocator, reader, options);
        } else if (std.mem.eql(u8, field_name, "PerspectiveFOVRad")) {
            result.mPerspectiveFOVRad = try std.json.innerParse(f32, frame_allocator, reader, options);
        } else if (std.mem.eql(u8, field_name, "PerspectiveNear")) {
            result.mPerspectiveNear = try std.json.innerParse(f32, frame_allocator, reader, options);
        } else if (std.mem.eql(u8, field_name, "PerspectiveFar")) {
            result.mPerspectiveFar = try std.json.innerParse(f32, frame_allocator, reader, options);
        } else if (std.mem.eql(u8, field_name, "AreaRect")) {
            result.mAreaRect = try std.json.innerParse(Vec4(f32), frame_allocator, reader, options);
        }
    }
    result.RecalculateProjection();

    return result;
}

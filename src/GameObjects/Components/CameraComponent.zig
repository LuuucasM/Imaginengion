const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const Vec4f32 = @import("../../Math/LinAlg.zig").Vec4f32;
const CameraComponent = @This();

const LinAlg = @import("../../Math/LinAlg.zig");
const Mat4f32 = LinAlg.Mat4f32;

//IMGUI
const imgui = @import("../../Core/CImports.zig").imgui;
const EditorWindow = @import("../../Imgui/EditorWindow.zig");

pub const ProjectionType = enum {
    Perspective,
    Orthographic,
};

mProjection: Mat4f32 = LinAlg.InitMat4CompTime(1.0),
mProjectionType: ProjectionType = .Perspective,

mAspectRatio: f32 = 0.0,
mIsFixedAspectRatio: bool = false,

mOrthographicSize: f32 = 10.0,
mOrthographicNear: f32 = -1.0,
mOrthographicFar: f32 = 1.0,

mPerspectiveFOV: f32 = LinAlg.DegreesToRadians(45.0),
mPerspectiveNear: f32 = 0.01,
mPerspectiveFar: f32 = 1000.0,

pub fn SetOrthographic(self: CameraComponent, size: f32, near_clip: f32, far_clip: f32) void {
    self.mOrthographicSize = size;
    self.mOrthographicNear = near_clip;
    self.mOrthographicFar = far_clip;
    self.RecalculateProjection();
}

pub fn SetPerspective(self: CameraComponent, fov: f32, near_clip: f32, far_clip: f32) void {
    self.mPerspectiveFOV = fov;
    self.mPerspectiveNear = near_clip;
    self.mPerspectiveFar = far_clip;
    self.RecalculateProjection();
}

pub fn SetProjectionType(self: CameraComponent, new_projection_type: ProjectionType) void {
    self.mProjectionType = new_projection_type;
    self.RecalculateProjection();
}

pub fn SetViewportSize(self: CameraComponent, width: usize, height: usize) void {
    if (height > 0) {
        self.mAspectRatio = @as(f32, @floatCast(width)) / @as(f32, @floatCast(height));
    } else {
        self.mAspectRatio = 0.0;
    }
    self.RecalculateProjection();
}

fn RecalculateProjection(self: CameraComponent) void {
    if (self.mProjectionType == .Perspective) {
        self.mProjection = LinAlg.PerspectiveRHNO(self.mPerspectiveFOV, self.mAspectRatio, self.mPerspectiveNear, self.mPerspectiveFar);
    } else {
        const ortho_left = -1.0 * self.mOrthographicSize * self.mAspectRatio * 0.5;
        const ortho_right = self.mOrthographicSize * self.mAspectRatio * 0.5;
        const ortho_bottom = 1.0 * self.mOrthographicSize * 0.5;
        const ortho_top = self.mOrthographicSize * 0.5;

        self.mProjection = LinAlg.OrthographicRHNO(ortho_left, ortho_right, ortho_bottom, ortho_top, self.mOrthographicNear, self.mOrthographicFar);
    }
}

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == CameraComponent) {
            break :blk i;
        }
    }
};

pub fn GetEditorWindow(self: *CameraComponent) EditorWindow {
    return EditorWindow.Init(self);
}

pub fn GetName(self: CameraComponent) []const u8 {
    _ = self;
    return "CameraComponent";
}

pub fn GetInd(self: CameraComponent) u32 {
    _ = self;
    return @intCast(Ind);
}

pub fn EditorRender(self: *CameraComponent) !void {
    _ = self;
}

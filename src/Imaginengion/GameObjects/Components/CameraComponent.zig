const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const Vec4f32 = @import("../../Math/LinAlg.zig").Vec4f32;
const CameraComponent = @This();

const LinAlg = @import("../../Math/LinAlg.zig");
const Mat4f32 = LinAlg.Mat4f32;

//IMGUI
const imgui = @import("../../Core/CImports.zig").imgui;
const EditorWindow = @import("../../Imgui/EditorWindow.zig");

pub const ProjectionType = enum(u1) {
    Perspective = 0,
    Orthographic = 1,
};

mProjection: Mat4f32 = LinAlg.Mat4Identity(),
mProjectionType: ProjectionType = .Perspective,

mAspectRatio: f32 = 0.0,
mIsFixedAspectRatio: bool = false,

mOrthographicSize: f32 = 10.0,
mOrthographicNear: f32 = -1.0,
mOrthographicFar: f32 = 1.0,

mPerspectiveFOVRad: f32 = LinAlg.DegreesToRadians(45.0),
mPerspectiveNear: f32 = 0.01,
mPerspectiveFar: f32 = 1000.0,

pub fn Deinit(_: *CameraComponent) !void {}

pub fn SetOrthographic(self: *CameraComponent, size: f32, near_clip: f32, far_clip: f32) void {
    self.mOrthographicSize = size;
    self.mOrthographicNear = near_clip;
    self.mOrthographicFar = far_clip;
    self.RecalculateProjection();
}

pub fn SetPerspective(self: *CameraComponent, fov_radians: f32, near_clip: f32, far_clip: f32) void {
    self.mPerspectiveFOVRad = fov_radians;
    self.mPerspectiveNear = near_clip;
    self.mPerspectiveFar = far_clip;
    self.RecalculateProjection();
}

pub fn SetProjectionType(self: *CameraComponent, new_projection_type: ProjectionType) void {
    self.mProjectionType = new_projection_type;
    self.RecalculateProjection();
}

pub fn SetViewportSize(self: *CameraComponent, width: usize, height: usize) void {
    if (height > 0) {
        self.mAspectRatio = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height));
    } else {
        self.mAspectRatio = 0.0;
    }
    self.RecalculateProjection();
}

fn RecalculateProjection(self: *CameraComponent) void {
    if (self.mProjectionType == .Perspective) {
        self.mProjection = LinAlg.PerspectiveRHNO(self.mPerspectiveFOVRad, self.mAspectRatio, self.mPerspectiveNear, self.mPerspectiveFar);
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

    //aspect ratio
    _ = imgui.igCheckbox("Set fixed aspect ratio", &self.mIsFixedAspectRatio);

    //projection type
    if (imgui.igBeginCombo("Projection type", @tagName(self.mProjectionType), imgui.ImGuiComboFlags_None) == true) {
        defer imgui.igEndCombo();
        if (imgui.igSelectable_Bool("Perspective", if (self.mProjectionType == .Perspective) true else false, imgui.ImGuiSelectableFlags_None, imgui.ImVec2{ .x = 50, .y = 50 })) {
            self.mProjectionType = .Perspective;
            self.RecalculateProjection();
        }
        if (imgui.igSelectable_Bool("Orthographic", if (self.mProjectionType == .Orthographic) true else false, imgui.ImGuiSelectableFlags_None, imgui.ImVec2{ .x = 50, .y = 50 })) {
            self.mProjectionType = .Orthographic;
            self.RecalculateProjection();
        }
    }

    //print the size/far/near variables depending on projection type
    if (self.mProjectionType == .Perspective) {
        var perspective_degrees = LinAlg.RadiansToDegrees(self.mPerspectiveFOVRad);
        if (imgui.igDragFloat("FOV", &perspective_degrees, 1.0, 0.0, 0.0, "%.3f", imgui.ImGuiSliderFlags_None) == true) {
            self.mPerspectiveFOVRad = LinAlg.DegreesToRadians(perspective_degrees);
            self.RecalculateProjection();
        }

        if (imgui.igDragFloat("Near", &self.mPerspectiveNear, 1.0, 0.0, 0.0, "%.3f", imgui.ImGuiSliderFlags_None) == true) {
            self.RecalculateProjection();
        }

        if (imgui.igDragFloat("Far", &self.mPerspectiveFar, 1.0, 0.0, 0.0, "%.3f", imgui.ImGuiSliderFlags_None) == true) {
            self.RecalculateProjection();
        }
    } else {
        if (imgui.igDragFloat("Size", &self.mOrthographicSize, 1.0, 0.0, 0.0, "%.3f", imgui.ImGuiSliderFlags_None) == true) {
            self.RecalculateProjection();
        }

        if (imgui.igDragFloat("Near", &self.mOrthographicNear, 1.0, 0.0, 0.0, "%.3f", imgui.ImGuiSliderFlags_None) == true) {
            self.RecalculateProjection();
        }

        if (imgui.igDragFloat("Far", &self.mOrthographicFar, 1.0, 0.0, 0.0, "%.3f", imgui.ImGuiSliderFlags_None) == true) {
            self.RecalculateProjection();
        }
    }
}

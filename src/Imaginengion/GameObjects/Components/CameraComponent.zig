const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const Vec4f32 = @import("../../Math/LinAlg.zig").Vec4f32;
const FrameBuffer = @import("../../FrameBuffers/FrameBuffer.zig");
const VertexArray = @import("../../VertexArrays/VertexArray.zig");
const VertexBuffer = @import("../../VertexBuffers/VertexBuffer.zig");
const IndexBuffer = @import("../../IndexBuffers/IndexBuffer.zig");
const AssetHandle = @import("../../Assets/AssetHandle.zig");
const AssetManager = @import("../../Assets/AssetManager.zig");

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

//viewport stuff
//TODO: finish changing this to use the new framebuffer system
mViewportWidth: usize = 0,
mViewportHeight: usize = 0,
mViewportFrameBuffer: FrameBuffer = undefined,
mViewportVertexArray: VertexArray = undefined,
mViewportVertexBuffer: VertexBuffer = undefined,
mViewportIndexBuffer: IndexBuffer = undefined,

mProjection: Mat4f32 = LinAlg.Mat4Identity(),

mAspectRatio: f32 = 0.0,
mIsFixedAspectRatio: bool = false,

mPerspectiveFOVRad: f32 = LinAlg.DegreesToRadians(60.0),
mPerspectiveNear: f32 = 0.01,
mPerspectiveFar: f32 = 1000.0,
mAreaRect: Vec4f32 = Vec4f32{ 0.0, 0.0, 1.0, 1.0 },

pub fn Deinit(self: *CameraComponent) !void {
    self.mViewportFrameBuffer.Deinit();
    self.mViewportVertexArray.Deinit();
    self.mViewportVertexBuffer.Deinit();
    self.mViewportIndexBuffer.Deinit();
}

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

pub fn SetAreaRect(self: *CameraComponent, new_area: Vec4f32) void {
    self.mAreaRect = new_area;
    self.mViewportFrameBuffer.Resize(@intFromFloat(@as(f32, @floatFromInt(self.mViewportWidth)) * self.mAreaRect[2]), @intFromFloat(@as(f32, @floatFromInt(self.mViewportHeight)) * self.mAreaRect[3]));
}

pub fn SetViewportSize(self: *CameraComponent, width: usize, height: usize) void {
    self.mViewportWidth = width;
    self.mViewportHeight = height;

    self.mViewportFrameBuffer.Resize(@intFromFloat(@as(f32, @floatFromInt(self.mViewportWidth)) * self.mAreaRect[2]), @intFromFloat(@as(f32, @floatFromInt(self.mViewportHeight)) * self.mAreaRect[3]));

    if (height > 0) {
        self.mAspectRatio = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height));
    } else {
        self.mAspectRatio = 0.0;
    }
    self.RecalculateProjection();
}

fn RecalculateProjection(self: *CameraComponent) void {
    self.mProjection = LinAlg.PerspectiveRHNO(self.mPerspectiveFOVRad, self.mAspectRatio, self.mPerspectiveNear, self.mPerspectiveFar);
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

    //print the size/far/near variables depending on projection type
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

    var rect_area: [4]f32 = [4]f32{ self.mAreaRect[0], self.mAreaRect[1], self.mAreaRect[2], self.mAreaRect[3] };

    if (imgui.igDragFloat4("Area Rect", &rect_area[0], 0.01, 0.0, 1.0, "%.3f", imgui.ImGuiSliderFlags_None)) {
        self.SetAreaRect(Vec4f32{ rect_area[0], rect_area[1], rect_area[2], rect_area[3] });
    }
}

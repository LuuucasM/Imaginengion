const std = @import("std");
const imgui = @import("../Core/CImports.zig").imgui;
const Vec2f32 = @import("../Math/LinAlg.zig").Vec2f32;
const FrameBuffer = @import("../FrameBuffers/FrameBuffer.zig");
const EditorCamera = @import("ViewportCamera.zig");

const ImguiManager = @import("Imgui.zig");
const ImguiEvent = @import("ImguiEvent.zig").ImguiEvent;
const InputEvents = @import("../Events/InputEvents.zig");
const Entity = @import("../GameObjects/Entity.zig");
const TransformComponent = @import("../GameObjects/Components.zig").TransformComponent;
const InputManager = @import("../Inputs/Input.zig");
const LinAlg = @import("../Math/LinAlg.zig");
const Vec3f32 = LinAlg.Vec3f32;
const Quatf32 = LinAlg.Quatf32;

const ViewportPanel = @This();

const GizmoType = enum(c_uint) {
    None = 0,
    Translate = imgui.TRANSLATE,
    Rotation = imgui.ROTATE,
    Scale = imgui.SCALE,
};

mP_Open: bool,
mViewportWidth: usize,
mViewportHeight: usize,
mViewportCamera: EditorCamera,
mSelectedEntity: ?Entity,
mGizmoType: GizmoType,

pub fn Init() ViewportPanel {
    return ViewportPanel{
        .mP_Open = true,
        .mViewportWidth = 1600,
        .mViewportHeight = 900,
        .mViewportCamera = EditorCamera.Init(1600, 900),
        .mSelectedEntity = null,
        .mGizmoType = .None,
    };
}

pub fn OnUpdate(self: *ViewportPanel) void {
    self.mViewportCamera.InputUpdate();
}

pub fn OnImguiRender(self: *ViewportPanel, scene_frame_buffer: *FrameBuffer) !void {
    if (self.mP_Open == false) return;
    _ = imgui.igBegin("Viewport", null, 0);
    defer imgui.igEnd();

    //update viewport size if needed
    var viewport_size: imgui.struct_ImVec2 = .{ .x = 0, .y = 0 };
    imgui.igGetContentRegionAvail(&viewport_size);
    if (viewport_size.x != @as(f32, @floatFromInt(self.mViewportWidth)) or viewport_size.y != @as(f32, @floatFromInt(self.mViewportHeight))) {
        //viewport resize event
        if (viewport_size.x < 0) viewport_size.x = 0;
        if (viewport_size.y < 0) viewport_size.y = 0;
        const new_imgui_event = ImguiEvent{
            .ET_ViewportResizeEvent = .{
                .mWidth = @intFromFloat(viewport_size.x),
                .mHeight = @intFromFloat(viewport_size.y),
            },
        };
        try ImguiManager.InsertEvent(new_imgui_event);
        self.mViewportWidth = @intFromFloat(viewport_size.x);
        self.mViewportHeight = @intFromFloat(viewport_size.y);
        self.mViewportCamera.SetViewportSize(@intFromFloat(viewport_size.x), @intFromFloat(viewport_size.y));
    }

    //render framebuffer
    const texture_id = @as(*anyopaque, @ptrFromInt(@as(usize, scene_frame_buffer.GetColorAttachmentID(0))));
    imgui.igImage(
        texture_id,
        imgui.struct_ImVec2{ .x = @floatFromInt(self.mViewportWidth), .y = @floatFromInt(self.mViewportHeight) },
        imgui.struct_ImVec2{ .x = 0.0, .y = 0.0 },
        imgui.struct_ImVec2{ .x = 1.0, .y = 1.0 },
        imgui.struct_ImVec4{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 },
        imgui.struct_ImVec4{ .x = 1.0, .y = 1.0, .z = 0.0, .w = 0.0 },
    );
    //drag drop target for scenes
    //entity picking for selected entity

    //gizmos
    if (self.mSelectedEntity) |entity| {
        if (self.mGizmoType != .None) {
            var window_pos: imgui.struct_ImVec2 = undefined;
            var window_size: imgui.struct_ImVec2 = undefined;
            imgui.igGetWindowPos(&window_pos);
            imgui.igGetWindowSize(&window_size);

            var viewport_bounds: [2]imgui.struct_ImVec2 = undefined;
            viewport_bounds[0] = imgui.struct_ImVec2{ .x = window_pos.x, .y = window_pos.y };
            viewport_bounds[1] = imgui.struct_ImVec2{ .x = window_pos.x + window_size.x, .y = window_pos.y + window_size.y };

            imgui.ImGuizmo_SetOrthographic(false);
            imgui.ImGuizmo_SetDrawlist(imgui.igGetWindowDrawList());
            imgui.ImGuizmo_SetRect(viewport_bounds[0].x, viewport_bounds[0].y, viewport_bounds[1].x - viewport_bounds[0].x, viewport_bounds[1].y - viewport_bounds[0].y);

            imgui.ImGuizmo_SetOrthographic(if (self.mViewportCamera.mProjectionType == .Orthographic) true else false);
            var camera_proj = LinAlg.Mat4ToArray(self.mViewportCamera.GetProjection());
            camera_proj[1][1] *= -1;
            var camera_view = LinAlg.Mat4ToArray(self.mViewportCamera.GetViewMatrix());

            const entity_transform_component = entity.GetComponent(TransformComponent);
            var entity_transform = LinAlg.Mat4ToArray(entity_transform_component.GetTransformMatrix());

            const snap_value: f32 = if (self.mGizmoType != .Rotation) 0.5 else 30.0;
            const snap_values: [3]f32 = [3]f32{ snap_value, snap_value, snap_value };

            _ = imgui.ImGuizmo_Manipulate(
                &camera_view[0][0],
                &camera_proj[0][0],
                @intFromEnum(self.mGizmoType),
                imgui.LOCAL,
                &entity_transform[0][0],
                null,
                if (InputManager.IsKeyPressed(.LeftControl) == true) &snap_values else null,
                null,
                null,
            );

            if (imgui.ImGuizmo_IsUsing() == true) {
                var translation: Vec3f32 = undefined;
                var rotation: Quatf32 = undefined;
                var scale: Vec3f32 = undefined;

                LinAlg.Decompose(entity_transform, &translation, &rotation, &scale);

                entity_transform_component.Translation = translation;
                entity_transform_component.Rotation = rotation;
                entity_transform_component.Scale = scale;
                entity_transform_component.Dirty = true;
            }
        }
    }
}

pub fn OnTogglePanelEvent(self: *ViewportPanel) void {
    self._PmOpen = !self.mP_Open;
}

pub fn OnSelectEntityEvent(self: *ViewportPanel, new_entity: ?Entity) void {
    self.mSelectedEntity = new_entity;
}

pub fn OnKeyPressedEvent(self: *ViewportPanel, e: InputEvents.KeyPressedEvent) bool {
    if (e._RepeatCount > 0) {
        return false;
    }
    switch (e._KeyCode) {
        .Q => {
            if (imgui.ImGuizmo_IsUsing() == false) {
                self.mGizmoType = .None;
            }
        },
        .W => {
            if (imgui.ImGuizmo_IsUsing() == false) {
                self.mGizmoType = .Translate;
            }
        },
        .E => {
            if (imgui.ImGuizmo_IsUsing() == false) {
                self.mGizmoType = .Rotation;
            }
        },
        .R => {
            if (imgui.ImGuizmo_IsUsing() == false) {
                self.mGizmoType = .Scale;
            }
        },
        else => return false,
    }
    return false;
}

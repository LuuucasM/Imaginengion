const std = @import("std");
const imgui = @import("../Core/CImports.zig").imgui;
const Vec2f32 = @import("../Math/LinAlg.zig").Vec2f32;
const FrameBuffer = @import("../FrameBuffers/FrameBuffer.zig");
const WindowResizeEvent = @import("../Events/SystemEvent.zig").WindowResizeEvent;

const ImguiEventManager = @import("../Events/ImguiEventManager.zig");
const ImguiEvent = @import("../Events/ImguiEvent.zig").ImguiEvent;
const InputPressedEvent = @import("../Events/SystemEvent.zig").InputPressedEvent;
const Entity = @import("../GameObjects/Entity.zig");
const Components = @import("../GameObjects/Components.zig");
const TransformComponent = Components.TransformComponent;
const CameraComponent = Components.CameraComponent;
const GameObjectUtils = @import("../GameObjects/GameObjectUtils.zig");
const SceneLayer = @import("../Scene/SceneLayer.zig");
const StaticInputContext = @import("../Inputs/Input.zig");

const LinAlg = @import("../Math/LinAlg.zig");
const Vec3f32 = LinAlg.Vec3f32;
const Quatf32 = LinAlg.Quatf32;
const Mat4f32 = LinAlg.Mat4f32;

const ProjectionType = @import("../GameObjects/Components.zig").CameraComponent.ProjectionType;

const ViewportPanel = @This();

const GizmoType = enum(c_int) {
    None = 0,
    Translate = imgui.TRANSLATE,
    Rotation = imgui.ROTATE,
    Scale = imgui.SCALE,
};

mP_Open: bool,
mViewportWidth: usize,
mViewportHeight: usize,
mSelectedEntity: ?Entity,
mGizmoType: GizmoType,
mIsFocused: bool = false,

pub fn Init(viewport_width: usize, viewport_height: usize) ViewportPanel {
    return ViewportPanel{
        .mP_Open = true,
        .mViewportWidth = viewport_width,
        .mViewportHeight = viewport_height,
        .mSelectedEntity = null,
        .mGizmoType = .None,
        .mIsFocused = false,
    };
}

pub fn OnImguiRender(self: *ViewportPanel, scene_frame_buffer: *FrameBuffer, camera_component: *CameraComponent, camera_transform: *TransformComponent) !void {
    _ = camera_component;
    _ = camera_transform;
    if (self.mP_Open == false) return;
    _ = imgui.igBegin("Viewport", null, 0);
    defer imgui.igEnd();

    //update viewport size if needed
    var viewport_size: imgui.struct_ImVec2 = .{ .x = 0, .y = 0 };
    imgui.igGetContentRegionAvail(&viewport_size);
    if (viewport_size.x != @as(f32, @floatFromInt(self.mViewportWidth)) or viewport_size.y != @as(f32, @floatFromInt(self.mViewportHeight))) {
        if (viewport_size.x < 0) viewport_size.x = 0;
        if (viewport_size.y < 0) viewport_size.y = 0;
        const new_imgui_event = ImguiEvent{
            .ET_ViewportResizeEvent = .{
                .mWidth = @intFromFloat(viewport_size.x),
                .mHeight = @intFromFloat(viewport_size.y),
            },
        };
        try ImguiEventManager.Insert(new_imgui_event);
        self.mViewportWidth = @intFromFloat(viewport_size.x);
        self.mViewportHeight = @intFromFloat(viewport_size.y);
    }

    //get if the window is focused or not
    self.mIsFocused = imgui.igIsWindowFocused(imgui.ImGuiFocusedFlags_None);

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
    if (imgui.igBeginDragDropTarget() == true) {
        defer imgui.igEndDragDropTarget();
        if (imgui.igAcceptDragDropPayload("IMSCLoad", imgui.ImGuiDragDropFlags_None)) |payload| {
            const path_len = payload.*.DataSize;
            const path = @as([*]const u8, @ptrCast(@alignCast(payload.*.Data)))[0..@intCast(path_len)];
            const new_event = ImguiEvent{
                .ET_OpenSceneEvent = .{
                    .Path = try ImguiEventManager.EventAllocator().dupe(u8, path),
                },
            };
            try ImguiEventManager.Insert(new_event);
        }
    }

    //TODO: entity picking for selected entity
    //TODO: gizmos to drag around entities in the viewport
}

pub fn OnImguiRenderPlay(self: *ViewportPanel, scene_frame_buffer: *FrameBuffer) !void {
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
        try ImguiEventManager.Insert(new_imgui_event);
        self.mViewportWidth = @intFromFloat(viewport_size.x);
        self.mViewportHeight = @intFromFloat(viewport_size.y);
    }

    //get if the window is focused or not
    self.mIsFocused = imgui.igIsWindowFocused(imgui.ImGuiFocusedFlags_None);

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
}

pub fn OnTogglePanelEvent(self: *ViewportPanel) void {
    self.mP_Open = !self.mP_Open;
}

pub fn OnSelectEntityEvent(self: *ViewportPanel, new_entity: ?Entity) void {
    self.mSelectedEntity = new_entity;
}

pub fn OnInputPressedEvent(self: *ViewportPanel, e: InputPressedEvent) bool {
    switch (e._InputCode) {
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
        else => return true,
    }
    return true;
}

pub fn OnWindowResize(self: *ViewportPanel, _: usize, _: usize) !bool {
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
        try ImguiEventManager.Insert(new_imgui_event);
        self.mViewportWidth = @intFromFloat(viewport_size.x);
        self.mViewportHeight = @intFromFloat(viewport_size.y);
    }
    return true;
}

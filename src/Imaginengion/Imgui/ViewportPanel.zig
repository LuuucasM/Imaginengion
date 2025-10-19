const std = @import("std");
const imgui = @import("../Core/CImports.zig").imgui;
const Vec2f32 = @import("../Math/LinAlg.zig").Vec2f32;
const FrameBuffer = @import("../FrameBuffers/FrameBuffer.zig");
const WindowResizeEvent = @import("../Events/SystemEvent.zig").WindowResizeEvent;

const ImguiEventManager = @import("../Events/ImguiEventManager.zig");
const ImguiEvent = @import("../Events/ImguiEvent.zig").ImguiEvent;
const InputPressedEvent = @import("../Events/SystemEvent.zig").InputPressedEvent;
const Entity = @import("../GameObjects/Entity.zig");
const EntityComponents = @import("../GameObjects/Components.zig");
const EntityTransformComponent = EntityComponents.TransformComponent;
const EntityCameraComponent = EntityComponents.CameraComponent;
const GameObjectUtils = @import("../GameObjects/GameObjectUtils.zig");
const SceneLayer = @import("../Scene/SceneLayer.zig");
const StaticInputContext = @import("../Inputs/Input.zig");

const LinAlg = @import("../Math/LinAlg.zig");
const Vec3f32 = LinAlg.Vec3f32;
const Quatf32 = LinAlg.Quatf32;
const Mat4f32 = LinAlg.Mat4f32;

const ProjectionType = @import("../GameObjects/Components.zig").CameraComponent.ProjectionType;

const Tracy = @import("../Core/Tracy.zig");

const ViewportPanel = @This();

const GizmoType = enum(c_int) {
    None = 0,
    Translate = imgui.TRANSLATE,
    Rotation = imgui.ROTATE,
    Scale = imgui.SCALE,
};

//for viewport window
mP_OpenViewport: bool = true,
mIsFocusedViewport: bool = false,
mViewportWidth: usize = 0,
mViewportHeight: usize = 0,
mSelectedEntity: ?Entity = null,
mGizmoType: GizmoType = .None,

//for play window
mP_OpenPlay: bool = true,
mIsFocusedPlay: bool = false,
mPlayWidth: usize = 0,
mPlayHeight: usize = 0,

pub fn Init(self: *ViewportPanel, viewport_width: usize, viewport_height: usize) void {
    self.mViewportWidth = viewport_width;
    self.mViewportHeight = viewport_height;

    self.mPlayWidth = viewport_width;
    self.mPlayHeight = viewport_height;
}

pub fn OnImguiRenderViewport(self: *ViewportPanel, camera_components: std.ArrayList(*EntityCameraComponent), camera_transforms: std.ArrayList(*EntityTransformComponent)) !void {
    _ = camera_transforms;

    const zone = Tracy.ZoneInit("ViewportPanel OIR", @src());
    defer zone.Deinit();

    if (self.mP_OpenViewport == false) return;

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
    self.mIsFocusedViewport = imgui.igIsWindowFocused(imgui.ImGuiFocusedFlags_None);

    try OnImguiRender(camera_components, viewport_size);

    //TODO: entity picking for selected entity
    //TODO: gizmos to drag around entities in the viewport
}

pub fn OnImguiRenderPlay(self: *ViewportPanel, camera_components: std.ArrayList(*EntityCameraComponent)) !void {
    const zone = Tracy.ZoneInit("PlayPanel OIR", @src());
    defer zone.Deinit();

    if (self.mP_OpenPlay == false) return;

    _ = imgui.igBegin("PlayPanel", null, 0);
    defer imgui.igEnd();

    //update viewport size if needed
    var viewport_size: imgui.struct_ImVec2 = .{ .x = 0, .y = 0 };
    imgui.igGetContentRegionAvail(&viewport_size);
    if (viewport_size.x != @as(f32, @floatFromInt(self.mPlayWidth)) or viewport_size.y != @as(f32, @floatFromInt(self.mPlayHeight))) {
        if (viewport_size.x < 0) viewport_size.x = 0;
        if (viewport_size.y < 0) viewport_size.y = 0;
        const new_imgui_event = ImguiEvent{
            .ET_PlayPanelResizeEvent = .{
                .mWidth = @intFromFloat(viewport_size.x),
                .mHeight = @intFromFloat(viewport_size.y),
            },
        };
        try ImguiEventManager.Insert(new_imgui_event);
        self.mPlayWidth = @intFromFloat(viewport_size.x);
        self.mPlayHeight = @intFromFloat(viewport_size.y);
    }

    //get if the window is focused or not
    self.mIsFocusedPlay = imgui.igIsWindowFocused(imgui.ImGuiFocusedFlags_None);

    try OnImguiRender(camera_components, viewport_size);
}

fn OnImguiRender(camera_components: std.ArrayList(*EntityCameraComponent), viewport_size: imgui.struct_ImVec2) !void {
    const zone = Tracy.ZoneInit("ImguiRender", @src());
    defer zone.Deinit();

    var viewport_pos: imgui.struct_ImVec2 = .{ .x = 0, .y = 0 };
    imgui.igGetCursorScreenPos(&viewport_pos);

    for (camera_components.items, 0..) |camera_component, i| {
        _ = i;
        const rect = camera_component.mAreaRect;
        const fb = camera_component.mViewportFrameBuffer;
        const texture_id = @as(*anyopaque, @ptrFromInt(@as(usize, fb.GetColorAttachmentID(0))));

        const x = viewport_pos.x + rect[0] * viewport_size.x;
        const y = viewport_pos.y + rect[1] * viewport_size.y;
        const w = rect[2] * viewport_size.x;
        const h = rect[3] * viewport_size.y;

        const draw_list = imgui.igGetWindowDrawList();
        imgui.ImDrawList_AddImage(
            draw_list,
            texture_id,
            .{ .x = x, .y = y },
            .{ .x = x + w, .y = y + h },
            .{ .x = 0, .y = 0 },
            .{ .x = 1, .y = 1 },
            0xFFFFFFFF,
        );
    }
}

pub fn OnTogglePanelEventViewport(self: *ViewportPanel) void {
    self.mP_OpenViewport = !self.mP_OpenViewport;
}

pub fn OnTogglePanelEventPlay(self: *ViewportPanel) void {
    self.mP_OpenPlay = !self.mP_OpenPlay;
}

pub fn OnSelectEntityEvent(self: *ViewportPanel, new_entity: ?Entity) void {
    self.mSelectedEntity = new_entity;
}

pub fn OnInputPressedEvent(self: *ViewportPanel, e: InputPressedEvent) bool {
    switch (e._InputCode) {
        .Q => {
            self.mGizmoType = .None;
        },
        .W => {
            self.mGizmoType = .Translate;
        },
        .E => {
            self.mGizmoType = .Rotation;
        },
        .R => {
            self.mGizmoType = .Scale;
        },
        else => return true,
    }
    return true;
}

pub fn OnDeleteEntity(self: *ViewportPanel, delete_entity: Entity) void {
    if (self.mSelectedEntity) |selected_entity| {
        if (selected_entity.mEntityID == delete_entity.mEntityID) {
            self.mSelectedEntity = null;
        }
    }
}

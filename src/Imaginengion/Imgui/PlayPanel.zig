const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const ImguiEvent = @import("../Events/ImguiEvent.zig").ImguiEvent;
const RenderStats = @import("../Renderer/Renderer.zig").RenderStats;
const FrameBuffer = @import("../FrameBuffers/FrameBuffer.zig");
const ImguiEventManager = @import("../Events/ImguiEventManager.zig");
const EntityComponents = @import("../GameObjects/Components.zig");
const EntityCameraComponent = EntityComponents.CameraComponent;
const EntityTransformComponent = EntityComponents.TransformComponent;
const Tracy = @import("../Core/Tracy.zig");
const PlayPanel = @This();

mP_Open: bool,
mViewportWidth: usize,
mViewportHeight: usize,
mIsFocused: bool = false,

pub fn Init() PlayPanel {
    return PlayPanel{
        .mP_Open = true,
        .mViewportWidth = 1280,
        .mViewportHeight = 720,
        .mIsFocused = false,
    };
}

pub fn OnImguiRender(self: *PlayPanel, camera_components: std.ArrayList(*EntityCameraComponent), camera_transforms: std.ArrayList(*EntityTransformComponent)) !void {
    _ = camera_transforms;
    if (self.mP_Open == false) return;

    const zone = Tracy.ZoneInit("PlayPanel OIR", @src());
    defer zone.Deinit();

    _ = imgui.igBegin("PlayPanel", null, 0);
    defer imgui.igEnd();

    //update viewport size if needed
    var viewport_size: imgui.struct_ImVec2 = .{ .x = 0, .y = 0 };
    imgui.igGetContentRegionAvail(&viewport_size);
    if (viewport_size.x != @as(f32, @floatFromInt(self.mViewportWidth)) or viewport_size.y != @as(f32, @floatFromInt(self.mViewportHeight))) {
        if (viewport_size.x < 0) viewport_size.x = 0;
        if (viewport_size.y < 0) viewport_size.y = 0;
        //TODO: change to its own PlayViewportRewizeEvent so that the main program can distinguish between play and viewport panel
        const new_imgui_event = ImguiEvent{
            .ET_PlayPanelResizeEvent = .{
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
    const draw_list = imgui.igGetWindowDrawList();

    var viewport_pos: imgui.ImVec2 = std.mem.zeroes(imgui.ImVec2);
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

pub fn OnTogglePanelEvent(self: *PlayPanel) void {
    self.mP_Open = !self.mP_Open;
}

const std = @import("std");
const imgui = @import("../Core/CImports.zig").imgui;
const Vec2f32 = @import("../Math/LinAlg.zig").Vec2f32;
const FrameBuffer = @import("../FrameBuffers/FrameBuffer.zig");
const EditorCamera = @import("ViewportCamera.zig");

const ImguiManager = @import("Imgui.zig");
const ImguiEvent = @import("ImguiEvent.zig").ImguiEvent;

const ViewportPanel = @This();

mP_Open: bool,
mViewportSize: Vec2f32,
mViewportCamera: EditorCamera,

pub fn Init() ViewportPanel {
    return ViewportPanel{
        .mP_Open = true,
        .mViewportSize = .{ 1600, 900 },
        .mViewportCamera = EditorCamera.Init(1600, 900),
    };
}

pub fn OnImguiRender(self: *ViewportPanel, scene_frame_buffer: *FrameBuffer) !void {
    if (self.mP_Open == false) return;
    _ = imgui.igBegin("Viewport", null, 0);
    defer imgui.igEnd();

    //update viewport size if needed
    var temp_viewport_size: imgui.struct_ImVec2 = .{ .x = 0, .y = 0 };
    imgui.igGetContentRegionAvail(&temp_viewport_size);
    if (temp_viewport_size.x != self.mViewportSize[0] or temp_viewport_size.y != self.mViewportSize[1]) {
        //viewport resize event
        if (temp_viewport_size.x < 0) temp_viewport_size.x = 0;
        if (temp_viewport_size.y < 0) temp_viewport_size.y = 0;
        const new_imgui_event = ImguiEvent{
            .ET_ViewportResizeEvent = .{
                .mWidth = @intFromFloat(temp_viewport_size.x),
                .mHeight = @intFromFloat(temp_viewport_size.y),
            },
        };
        try ImguiManager.InsertEvent(new_imgui_event);
        self.mViewportSize[0] = temp_viewport_size.x;
        self.mViewportSize[1] = temp_viewport_size.y;
        self.mViewportCamera.SetViewportSize(@intFromFloat(temp_viewport_size.x), @intFromFloat(temp_viewport_size.y));
    }

    //render framebuffer
    const texture_id = @as(*anyopaque, @ptrFromInt(@as(usize, scene_frame_buffer.GetColorAttachmentID(0))));
    imgui.igImage(
        texture_id,
        imgui.struct_ImVec2{ .x = self.mViewportSize[0], .y = self.mViewportSize[1] },
        imgui.struct_ImVec2{ .x = 0.0, .y = 0.0 },
        imgui.struct_ImVec2{ .x = 1.0, .y = 1.0 },
        imgui.struct_ImVec4{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 },
        imgui.struct_ImVec4{ .x = 1.0, .y = 1.0, .z = 0.0, .w = 0.0 },
    );
    //drag drop target for scenes
    //entity picking for selected entity
    //gizmo stuff
}

pub fn OnTogglePanelEvent(self: *ViewportPanel) void {
    self._PmOpen = !self.mP_Open;
}

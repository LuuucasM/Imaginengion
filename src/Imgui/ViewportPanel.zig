const std = @import("std");
const imgui = @import("../Core/CImports.zig").imgui;
const Vec2f32 = @import("../Math/LinAlg.zig").Vec2f32;
const FrameBuffer = @import("../FrameBuffers/InternalFrameBuffer.zig");
const EditorCamera = @import("../Camera/EditorCamera.zig");

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

pub fn OnImguiRender(self: *ViewportPanel) !void {
    if (self.mP_Open == false) return;
    _ = imgui.igBegin("Viewport", null, 0);
    defer imgui.igEnd();

    self.mViewportCamera.OnUpdate();

    //update viewport size if needed
    var temp_viewport_size: imgui.struct_ImVec2 = .{ .x = 0, .y = 0 };
    imgui.igGetContentRegionAvail(&temp_viewport_size);
    if (temp_viewport_size.x != self.mViewportSize[0] or temp_viewport_size.y != self.mViewportSize[1]) {
        //viewport resize event
        const new_imgui_event = ImguiEvent{
            .ET_ViewportResizeEvent = .{
                .mWidth = @intFromFloat(temp_viewport_size.x),
                .mHeight = @intFromFloat(temp_viewport_size.y),
            },
        };
        try ImguiManager.InsertEvent(new_imgui_event);
        self.mViewportSize[0] = temp_viewport_size.x;
        self.mViewportSize[1] = temp_viewport_size.y;
    }

    //render framebuffer
    //drag drop target for scenes
    //gizmo stuff
}

pub fn OnTogglePanelEvent(self: *ViewportPanel) void {
    self._PmOpen = !self.mP_Open;
}

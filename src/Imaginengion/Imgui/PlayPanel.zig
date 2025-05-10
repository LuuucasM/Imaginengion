const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const ImguiEvent = @import("../Events/ImguiEvent.zig").ImguiEvent;
const RenderStats = @import("../Renderer/Renderer.zig").RenderStats;
const FrameBuffer = @import("../FrameBuffers/FrameBuffer.zig");
const ImguiEventManager = @import("../Events/ImguiEventManager.zig");
const PlayPanel = @This();

mViewportWidth: usize,
mViewportHeight: usize,
mIsFocused: bool,

pub fn Init() PlayPanel {
    return PlayPanel{
        .mViewportWidth = 1280,
        .mViewportHeight = 720,
        .mIsFocused = false,
    };
}

pub fn OnImguiRender(self: *PlayPanel, scene_frame_buffer: *FrameBuffer) !void {
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

const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const ImguiEvent = @import("../Events/ImguiEvent.zig").ImguiEvent;
const AssetHandle = @import("../Assets/AssetHandle.zig");
const AssetManager = @import("../Assets/AssetManager.zig");
const ImguiManager = @import("Imgui.zig");
const Texture2D = @import("../Assets/Assets.zig").Texture2D;
const ToolbarPanel = @This();

pub const EditorState = enum {
    Play,
    Stop,
};

mP_Open: bool,
mState: EditorState,
mPlayIcon: AssetHandle,
mStopIcon: AssetHandle,

pub fn Init() !ToolbarPanel {
    return ToolbarPanel{
        .mP_Open = true,
        .mState = .Stop,
        .mPlayIcon = try AssetManager.GetAssetHandleRef("assets/textures/play.png"),
        .mStopIcon = try AssetManager.GetAssetHandleRef("assets/textures/stop.png"),
    };
}

pub fn OnImguiRender(self: *ToolbarPanel) !void {
    if (self.mP_Open == false) return;
    imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_WindowPadding, .{ .x = 0.0, .y = 2.0 });
    imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_ItemInnerSpacing, .{ .x = 0.0, .y = 0.0 });
    defer imgui.igPopStyleVar(2);

    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Button, .{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 });
    const colors = imgui.igGetStyle().*.Colors;
    const buttonHovered = colors[imgui.ImGuiCol_ButtonHovered];
    const buttonActive = colors[imgui.ImGuiCol_ButtonActive];
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonHovered, .{ .x = buttonHovered.x, .y = buttonHovered.y, .z = buttonHovered.z, .w = 0.5 });
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonActive, .{ .x = buttonActive.x, .y = buttonActive.y, .z = buttonActive.z, .w = 0.5 });
    defer imgui.igPopStyleColor(3);

    const config = imgui.ImGuiWindowFlags_NoDecoration | imgui.ImGuiWindowFlags_NoScrollbar | imgui.ImGuiWindowFlags_NoScrollWithMouse;
    _ = imgui.igBegin("##Toolbar", null, config);
    defer imgui.igEnd();

    const size = imgui.igGetWindowHeight();
    const texture: *Texture2D = if (self.mState == .Play) try self.mStopIcon.GetAsset(Texture2D) else try self.mPlayIcon.GetAsset(Texture2D);

    //ImGui::SameLine((ImGui::GetWindowContentRegionMax().x * 0.5f) - (size * 0.5f));
    var window_size: imgui.struct_ImVec2 = undefined;
    imgui.igGetContentRegionAvail(&window_size);
    imgui.igSameLine((window_size.x * 0.5) - (size * 0.5), 0.0);

    const texture_id = @as(*anyopaque, @ptrFromInt(@as(usize, texture.GetID())));

    if (imgui.igImageButtonEx(
        texture.GetID(),
        texture_id,
        .{ .x = size, .y = size },
        .{ .x = 0, .y = 0 },
        .{ .x = 1, .y = 1 },
        .{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 },
        .{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 },
        imgui.ImGuiButtonFlags_None,
    ) == true) {
        self.mState = if (self.mState == .Play) .Stop else .Play;
    }
}

pub fn OnTogglePanelEvent(self: *ToolbarPanel) void {
    self.mP_Open = !self.mP_Open;
}

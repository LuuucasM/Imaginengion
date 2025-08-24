const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const ImguiEvent = @import("../Events/ImguiEvent.zig").ImguiEvent;
const ImguiEventManager = @import("../Events/ImguiEventManager.zig");
const AssetHandle = @import("../Assets/AssetHandle.zig");
const AssetManager = @import("../Assets/AssetManager.zig");
const ImguiManager = @import("Imgui.zig");
const Texture2D = @import("../Assets/Assets.zig").Texture2D;
const SceneManager = @import("../Scene/SceneManager.zig");
const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;
const EntityComponents = @import("../GameObjects/Components.zig");
const CameraComponent = EntityComponents.CameraComponent;
const PlayerSlotComponent = EntityComponents.PlayerSlotComponent;
const EntityChildComponent = EntityComponents.ChildComponent;
const Entity = @import("../GameObjects/Entity.zig");
const Tracy = @import("../Core/Tracy.zig");
const ToolbarPanel = @This();

pub const EditorState = enum(u2) {
    Play = 0,
    Stop = 1,
};

mP_Open: bool,
mState: EditorState,
mPlayIcon: AssetHandle,
mStopIcon: AssetHandle,
mStartEntity: ?Entity,

pub fn Init() !ToolbarPanel {
    return ToolbarPanel{
        .mP_Open = true,
        .mState = .Stop,
        .mPlayIcon = try AssetManager.GetAssetHandleRef("assets/textures/play.png", .Eng),
        .mStopIcon = try AssetManager.GetAssetHandleRef("assets/textures/stop.png", .Eng),
        .mStartEntity = null,
    };
}

pub fn OnImguiRender(self: *ToolbarPanel, game_scene_manager: *SceneManager, frame_allocator: std.mem.Allocator) !void {
    const zone = Tracy.ZoneInit("ToolbarPanel OIR", @src());
    defer zone.Deinit();

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
    const texture: *Texture2D = if (self.mState == .Play) (try self.mStopIcon.GetAsset(Texture2D)).? else (try self.mPlayIcon.GetAsset(Texture2D)).?;

    var window_size: imgui.struct_ImVec2 = undefined;
    imgui.igGetContentRegionAvail(&window_size);

    // Center the group: calculate total width of button + combo + spacing
    const button_width = size;
    const combo_width: f32 = 120.0; // Estimate or measure your combo width
    const spacing: f32 = 8.0; // Default ImGui spacing
    const total_width = button_width + spacing + combo_width;
    const start_x = (window_size.x * 0.5) - (total_width * 0.5);

    imgui.igSetCursorPosX(start_x);

    // Button
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
        if (self.mStartEntity) |entity| {
            if (self.mState == .Stop) {
                try ImguiEventManager.Insert(ImguiEvent{
                    .ET_ChangeEditorStateEvent = .{ .mEditorState = .Play, .mStartEntity = entity },
                });
                self.mState = .Play;
            }
        }
        if (self.mState == .Play) {
            std.debug.assert(self.mStartEntity != null);
            try ImguiEventManager.Insert(ImguiEvent{
                .ET_ChangeEditorStateEvent = .{ .mEditorState = .Stop, .mStartEntity = null },
            });
            self.mState = .Stop;
        }
    }

    // Place combo box on the same line, with spacing
    imgui.igSameLine(0.0, spacing);

    // Combo box
    imgui.igPushItemWidth(combo_width); // combo_width should be wide enough, e.g., 120.0 or more

    var combo_text: []const u8 = "None\x00";
    if (self.mStartEntity) |entity| {
        // Ensure null-terminated string for ImGui
        var name_buf: [128]u8 = undefined;
        combo_text = try std.fmt.bufPrintZ(&name_buf, "{s}", .{entity.GetName()});
    }
    if (imgui.igBeginCombo("##PlayLocation", @ptrCast(combo_text.ptr), imgui.ImGuiComboFlags_None)) {
        defer imgui.igEndCombo();

        if (imgui.igSelectable_Bool("None\x00", self.mStartEntity == null, 0, .{ .x = 0, .y = 0 })) {
            self.mStartEntity = null;
        }

        const camera_entities = try game_scene_manager.GetEntityGroup(GroupQuery{ .Component = CameraComponent }, frame_allocator);

        for (camera_entities.items) |entity_id| {
            const entity = game_scene_manager.GetEntity(entity_id);

            if (entity.GetPossessable()) |possess_entity| {
                var name_buf: [128]u8 = undefined;
                const name_cstr = try std.fmt.bufPrintZ(&name_buf, "{s}", .{possess_entity.GetName()});
                if (self.mStartEntity) |start_entity| {
                    if (imgui.igSelectable_Bool(name_cstr, start_entity.mEntityID == possess_entity.mEntityID, 0, .{ .x = 0, .y = 0 })) {
                        self.mStartEntity = possess_entity;
                    }
                } else {
                    if (imgui.igSelectable_Bool(name_cstr, false, 0, .{ .x = 0, .y = 0 })) {
                        self.mStartEntity = possess_entity;
                    }
                }
            }
        }
    }
    imgui.igPopItemWidth();
}

pub fn OnTogglePanelEvent(self: *ToolbarPanel) void {
    self.mP_Open = !self.mP_Open;
}

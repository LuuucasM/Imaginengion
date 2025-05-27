const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const ImguiEvent = @import("../Events/ImguiEvent.zig").ImguiEvent;
const AssetManager = @import("../Assets/AssetManager.zig");
const Entity = @import("../GameObjects/Entity.zig");
const ScriptComponent = @import("../GameObjects/Components.zig").ScriptComponent;
const ImguiUtils = @import("ImguiUtils.zig");

const ScriptAsset = @import("../Assets/Assets.zig").ScriptAsset;
const Components = @import("../GameObjects/Components.zig");
const OnUpdateInputScript = Components.OnUpdateInputScript;

const GameObjectUtils = @import("../GameObjects/GameObjectUtils.zig");

const EntityType = @import("../Scene/SceneManager.zig").EntityType;

const ScriptsPanel = @This();

_P_Open: bool,
mSelectedEntity: ?Entity,

pub fn Init() ScriptsPanel {
    return ScriptsPanel{
        ._P_Open = true,
        .mSelectedEntity = null,
    };
}

pub fn OnImguiRender(self: ScriptsPanel) !void {
    if (self._P_Open == false) return;
    _ = imgui.igBegin("Scripts", null, 0);
    defer imgui.igEnd();

    var available_region: imgui.ImVec2 = undefined;
    imgui.igGetContentRegionAvail(&available_region);

    if (imgui.igIsWindowHovered(imgui.ImGuiHoveredFlags_None) == true and imgui.igIsMouseClicked_Bool(imgui.ImGuiMouseButton_Right, false) == true) {
        imgui.igOpenPopup_Str("RightClickPopup", imgui.ImGuiPopupFlags_None);
    }
    if (imgui.igBeginPopup("RightClickPopup", imgui.ImGuiWindowFlags_None) == true) {
        defer imgui.igEndPopup();
        try ImguiUtils.ScriptPopupMenu();
    }

    //making a child so that drag drop target will tae the entire available region
    if (imgui.igBeginChild_Str("SceneChild", available_region, imgui.ImGuiChildFlags_None, imgui.ImGuiWindowFlags_NoMove | imgui.ImGuiWindowFlags_NoScrollbar)) {
        defer imgui.igEndChild();
        if (self.mSelectedEntity) |entity| {
            if (entity.HasComponent(ScriptComponent)) {
                var ecs = entity.mECSManagerRef;
                var iter = entity.GetComponent(ScriptComponent);

                iter = ecs.GetComponent(ScriptComponent, iter.mFirst);
                if (imgui.igSelectable_Bool(@typeName(ScriptComponent), false, imgui.ImGuiSelectableFlags_None, .{ .x = 0, .y = 0 }) == true) {}
                while (iter.mNext != Entity.NullEntity) {
                    iter = ecs.GetComponent(ScriptComponent, iter.mNext);
                    if (imgui.igSelectable_Bool(@typeName(ScriptComponent), false, imgui.ImGuiSelectableFlags_None, .{ .x = 0, .y = 0 }) == true) {}
                }
            }
        }
    }
    //drag drop target for scripts
    if (imgui.igBeginDragDropTarget() == true) {
        defer imgui.igEndDragDropTarget();
        if (imgui.igAcceptDragDropPayload("ScriptPayload", imgui.ImGuiDragDropFlags_None)) |payload| {
            const path_len = payload.*.DataSize;
            const path = @as([*]const u8, @ptrCast(@alignCast(payload.*.Data)))[0..@intCast(path_len)];
            if (self.mSelectedEntity) |entity| {
                try GameObjectUtils.AddScriptToEntity(entity, path, .Prj);
            }
        }
    }
}

pub fn OnTogglePanelEvent(self: *ScriptsPanel) void {
    self._P_Open = !self._P_Open;
}

pub fn OnSelectEntityEvent(self: *ScriptsPanel, new_selected_entity: ?Entity) void {
    self.mSelectedEntity = new_selected_entity;
}

const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const ImguiEvent = @import("../Events/ImguiEvent.zig").ImguiEvent;
const AssetManager = @import("../Assets/AssetManager.zig");
const Entity = @import("../GameObjects/Entity.zig");
const ScriptComponent = @import("../GameObjects/Components.zig").ScriptComponent;

const ScriptAsset = @import("../Assets/Assets.zig").ScriptAsset;
const OnKeyPressedScriptTag = @import("../GameObjects/Components.zig").OnKeyPressedScriptTag;

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

    //making a child so that drag drop target will tae the entire available region
    if (imgui.igBeginChild_Str("SceneChild", available_region, imgui.ImGuiChildFlags_None, imgui.ImGuiWindowFlags_NoMove | imgui.ImGuiWindowFlags_NoScrollbar)) {
        defer imgui.igEndChild();
        if (self.mSelectedEntity) |entity| {
            if (entity.HasComponent(ScriptComponent)) {
                var ecs = entity.mSceneLayerRef.mECSManagerRef;
                var iter = entity.GetComponent(ScriptComponent);

                iter = ecs.GetComponent(ScriptComponent, iter.mFirst);
                if (imgui.igSelectable_Bool(@typeName(ScriptComponent), false, imgui.ImGuiSelectableFlags_None, .{ .x = 0, .y = 0 }) == true) {}
                while (iter.mNext != std.math.maxInt(u32)) {
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
                var ecs = entity.mSceneLayerRef.mECSManagerRef;
                var new_script_handle = try AssetManager.GetAssetHandleRef(path, .Prj);
                const script_asset = try new_script_handle.GetAsset(ScriptAsset);
                const new_script_entity = try ecs.CreateEntity();

                _ = switch (script_asset.mScriptType) {
                    .OnKeyPressed => try ecs.AddComponent(OnKeyPressedScriptTag, new_script_entity, null),
                };

                if (entity.HasComponent(ScriptComponent)) {

                    //entity already has a script so iterate until the end of the linked list
                    var iter_id = entity.GetComponent(ScriptComponent).mFirst;
                    var iter = ecs.GetComponent(ScriptComponent, iter_id);
                    while (iter.mNext != std.math.maxInt(u32)) {
                        iter_id = iter.mNext;
                        iter = ecs.GetComponent(ScriptComponent, iter.mNext);
                    }

                    iter.mNext = new_script_entity;

                    const new_script_component = ScriptComponent{
                        .mFirst = iter.mFirst,
                        .mNext = std.math.maxInt(u32),
                        .mParent = iter.mParent,
                        .mPrev = iter_id,
                        .mScriptAssetHandle = new_script_handle,
                    };
                    _ = try ecs.AddComponent(ScriptComponent, new_script_entity, new_script_component);
                } else {

                    //add the script component to the entity of interest
                    const entity_new_script_component = ScriptComponent{
                        .mFirst = new_script_entity,
                        .mNext = new_script_entity,
                        .mParent = std.math.maxInt(u32),
                        .mPrev = std.math.maxInt(u32),
                        .mScriptAssetHandle = .{ .mID = std.math.maxInt(u32) },
                    };
                    _ = try entity.AddComponent(ScriptComponent, entity_new_script_component);

                    //add script component to script entity
                    const new_script_component = ScriptComponent{
                        .mFirst = new_script_entity,
                        .mNext = std.math.maxInt(u32),
                        .mParent = entity.mEntityID,
                        .mPrev = std.math.maxInt(u32),
                        .mScriptAssetHandle = new_script_handle,
                    };
                    _ = try ecs.AddComponent(ScriptComponent, new_script_entity, new_script_component);
                }
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

const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const ImguiEvent = @import("../Events/ImguiEvent.zig").ImguiEvent;
const Entity = @import("../GameObjects/Entity.zig");
const EntityScriptComponent = @import("../GameObjects/Components.zig").ScriptComponent;
const ImguiUtils = @import("ImguiUtils.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const Assets = @import("../Assets/Assets.zig");
const FileMetaData = Assets.FileMetaData;
const ScriptAsset = Assets.ScriptAsset;
const Components = @import("../GameObjects/Components.zig");
const OnUpdateInputScript = Components.OnUpdateInputScript;

const GameObjectUtils = @import("../GameObjects/GameObjectUtils.zig");

const Tracy = @import("../Core/Tracy.zig");

const ScriptsPanel = @This();

_P_Open: bool = true,
mSelectedEntity: ?Entity = null,

pub fn Init(self: ScriptsPanel) void {
    _ = self;
}

pub fn OnImguiRender(self: ScriptsPanel, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("Scripts Panel OIR", @src());
    defer zone.Deinit();

    const frame_allocator = engine_context.FrameAllocator();

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
        try ImguiUtils.EntityScriptPopupMenu(engine_context);
    }

    //making a child so that drag drop target will tae the entire available region
    if (imgui.igBeginChild_Str("SceneChild", available_region, imgui.ImGuiChildFlags_None, imgui.ImGuiWindowFlags_NoMove | imgui.ImGuiWindowFlags_NoScrollbar)) {
        defer imgui.igEndChild();
        if (self.mSelectedEntity) |entity| {
            if (entity.GetComponent(EntityScriptComponent)) |script_component| {
                const ecs = entity.mECSManagerRef;

                var curr_id = script_component.mFirst;
                var curr_comp = ecs.GetComponent(EntityScriptComponent, curr_id).?;

                while (true) : (if (curr_id == script_component.mFirst) break) {
                    const asset_handle = curr_comp.mScriptAssetHandle;
                    const script_file_data = try asset_handle.GetAsset(engine_context, FileMetaData);

                    const script_name = try std.fmt.allocPrint(frame_allocator, "{s}###{d}", .{ std.fs.path.basename(script_file_data.mRelPath.items), curr_id });

                    if (imgui.igSelectable_Bool(script_name.ptr, false, imgui.ImGuiSelectableFlags_None, .{ .x = 0.0, .y = 0.0 })) {}

                    if (imgui.igBeginPopupContextItem(script_name.ptr, imgui.ImGuiPopupFlags_MouseButtonRight)) {
                        defer imgui.igEndPopup();

                        if (imgui.igMenuItem_Bool("Delete Component", "", false, true)) {
                            try engine_context.mGameEventManager.Insert(engine_context.EngineAllocator(), .{ .ET_RmEntityCompEvent = .{ .mEntityID = curr_id, .mComponentType = .ScriptComponent } });
                        }
                    }

                    curr_id = curr_comp.mNext;
                    curr_comp = ecs.GetComponent(EntityScriptComponent, curr_id).?;
                }
            }
        }
    }
    //drag drop target for scripts
    if (imgui.igBeginDragDropTarget() == true) {
        defer imgui.igEndDragDropTarget();
        if (imgui.igAcceptDragDropPayload("GameObjectScriptLoad", imgui.ImGuiDragDropFlags_None)) |payload| {
            const path_len = payload.*.DataSize;
            const rel_path = @as([*]const u8, @ptrCast(@alignCast(payload.*.Data)))[0..@intCast(path_len)];
            if (self.mSelectedEntity) |entity| {
                try GameObjectUtils.AddScriptToEntity(engine_context, entity, rel_path, .Prj);
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

pub fn OnDeleteEntity(self: *ScriptsPanel, delete_entity: Entity) void {
    if (self.mSelectedEntity) |selected_entity| {
        if (selected_entity.mEntityID == delete_entity.mEntityID) {
            self.mSelectedEntity = null;
        }
    }
}

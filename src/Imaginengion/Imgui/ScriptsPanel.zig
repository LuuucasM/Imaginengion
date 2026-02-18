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
const EntityParentComponent = @import("../ECS/Components.zig").ParentComponent(Entity.Type);
const EntityChildComponent = @import("../ECS/Components.zig").ChildComponent(Entity.Type);
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

    if (self._P_Open == false) return;

    if (self.mSelectedEntity) |entity| {
        const entity_name = entity.GetName();
        const name_len = std.mem.indexOf(u8, entity_name, &.{0}) orelse entity_name.len;
        const trimmed_name = entity_name[0..name_len];
        const name = try std.fmt.allocPrintSentinel(engine_context.FrameAllocator(), "Scripts - {s}###Scripts\x00", .{trimmed_name}, 0);

        _ = imgui.igBegin(name.ptr, null, 0);
    } else {
        _ = imgui.igBegin("Scripts - No Entity###Scripts\x00", null, 0);
    }
    defer imgui.igEnd();

    var available_region: imgui.ImVec2 = undefined;
    imgui.igGetContentRegionAvail(&available_region);

    //making a child so that drag drop target will tae the entire available region
    if (imgui.igBeginChild_Str("SceneChild", available_region, imgui.ImGuiChildFlags_None, imgui.ImGuiWindowFlags_NoMove | imgui.ImGuiWindowFlags_NoScrollbar)) {
        defer imgui.igEndChild();
        if (self.mSelectedEntity) |entity| {
            if (entity.GetComponent(EntityParentComponent)) |parent_component| {
                if (parent_component.mFirstScript != Entity.NullEntity) {
                    var curr_id = parent_component.mFirstScript;
                    while (true) : (if (curr_id == parent_component.mFirstScript) break) {
                        const script_entity = Entity{ .mEntityID = curr_id, .mECSManagerRef = entity.mECSManagerRef };

                        const script_name = script_entity.GetName();

                        if (imgui.igSelectable_Bool(script_name.ptr, false, imgui.ImGuiSelectableFlags_None, .{ .x = 0.0, .y = 0.0 })) {}

                        if (imgui.igBeginPopupContextItem(script_name.ptr, imgui.ImGuiPopupFlags_MouseButtonRight)) {
                            defer imgui.igEndPopup();

                            if (imgui.igMenuItem_Bool("Delete Script", "", false, true)) {
                                script_entity.Delete(engine_context);
                            }
                        }

                        const child_component = script_entity.GetComponent(EntityChildComponent).?;
                        curr_id = child_component.mNext;
                    }
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

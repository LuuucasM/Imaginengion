const std = @import("std");
const imgui = @import("../Core/CImports.zig").imgui;
const ImguiManager = @import("../Imgui/Imgui.zig");
const ImguiEvent = @import("ImguiEvent.zig").ImguiEvent;
const SceneLayer = @import("../Scene/SceneLayer.zig");
const Entity = @import("../GameObjects/Entity.zig");
const SparseSet = @import("../Vendor/zig-sparse-set/src/sparse_set.zig").SparseSet;
const ScenePanel = @This();

mIsVisible: bool,
mSelectedScene: ?usize,
mSelectedEntity: ?Entity,

pub fn Init() ScenePanel {
    return ScenePanel{
        .mIsVisible = true,
        .mSelectedScene = null,
        .mSelectedEntity = null,
    };
}

pub fn OnImguiRender(self: *ScenePanel, scene_stack_ref: *std.ArrayList(SceneLayer)) !void {
    if (self.mIsVisible == false) return;

    _ = imgui.igBegin("Scenes", null, 0);
    defer imgui.igEnd();

    var available_region: imgui.ImVec2 = undefined;
    imgui.igGetContentRegionAvail(&available_region);

    if (imgui.igBeginChild_Str("SceneChild", available_region, imgui.ImGuiChildFlags_None, imgui.ImGuiWindowFlags_NoMove | imgui.ImGuiWindowFlags_NoScrollbar)) {
        defer imgui.igEndChild();
        var i: usize = scene_stack_ref.items.len;
        while (i > 0) {
            i -= 1;
            const scene_layer = &scene_stack_ref.items[i];

            var name_buf: [260]u8 = undefined;
            const scene_name = try std.fmt.bufPrintZ(&name_buf, "{s}", .{scene_layer.mName.items});

            const selected_text_col = imgui.ImVec4{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 };
            const other_text_col = imgui.ImVec4{ .x = 0.7, .y = 0.7, .z = 0.7, .w = 1.0 };

            const io = imgui.igGetIO();
            const bold_font = io.*.Fonts.*.Fonts.Data[0];

            _ = imgui.igPushID_Str(scene_name.ptr);
            defer imgui.igPopID();

            if (self.mSelectedScene == scene_layer.mInternalID) {
                imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Text, selected_text_col);
                imgui.igPushFont(bold_font);
            } else {
                imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Text, other_text_col);
            }

            const tree_flags = imgui.ImGuiTreeNodeFlags_OpenOnArrow;
            const is_tree_open = imgui.igTreeNodeEx_Str(scene_name.ptr, tree_flags);
            if (self.mSelectedScene == scene_layer.mInternalID) {
                imgui.igPopFont();
            }
            imgui.igPopStyleColor(1);

            if (imgui.igIsItemClicked(imgui.ImGuiMouseButton_Left) == true) {
                self.mSelectedScene = scene_layer.mInternalID;
                try ImguiManager.InsertEvent(.{
                    .ET_SelectSceneEvent = .{
                        .SelectedScene = scene_layer.mInternalID,
                    },
                });
            }

            const draw_list = imgui.igGetWindowDrawList();
            var min_pos: imgui.ImVec2 = undefined;
            var max_pos: imgui.ImVec2 = undefined;
            imgui.igGetItemRectMin(&min_pos);
            imgui.igGetItemRectMax(&max_pos);
            if (scene_layer.mLayerType == .OverlayLayer) {
                imgui.ImDrawList_AddRect(draw_list, min_pos, max_pos, 0xFFEBCE87, 0.0, imgui.ImDrawFlags_None, 1.0);
            } else {
                imgui.ImDrawList_AddRect(draw_list, min_pos, max_pos, 0xFF84A4C4, 0.0, imgui.ImDrawFlags_None, 1.0);
            }

            if (imgui.igBeginDragDropSource(imgui.ImGuiDragDropFlags_None) == true) {
                defer imgui.igEndDragDropSource();
                _ = imgui.igSetDragDropPayload("SceneMove", @ptrCast(&scene_layer.mInternalID), @sizeOf(usize), imgui.ImGuiCond_Once);
            }

            if (imgui.igBeginDragDropTarget() == true) {
                defer imgui.igEndDragDropTarget();
                if (imgui.igAcceptDragDropPayload("SceneMove", imgui.ImGuiDragDropFlags_None)) |payload| {
                    const payload_internal_id = @as(*usize, @ptrCast(@alignCast(payload.*.Data))).*;
                    const payload_scene = scene_stack_ref.items[payload_internal_id];
                    const current_pos = payload_scene.mInternalID;
                    const new_pos = i;
                    if (current_pos != new_pos) {
                        const new_event = ImguiEvent{
                            .ET_MoveSceneEvent = .{
                                .SceneID = current_pos,
                                .NewPos = new_pos,
                            },
                        };
                        try ImguiManager.InsertEvent(new_event);
                        if (new_pos < current_pos) {
                            if (self.mSelectedScene) |scene_id| {
                                if (new_pos <= scene_id and scene_id < current_pos) {
                                    self.mSelectedScene.? += 1;
                                }
                            }
                        } else {
                            if (self.mSelectedScene) |scene_id| {
                                if (current_pos < scene_id and scene_id <= new_pos) {
                                    self.mSelectedScene.? -= 1;
                                }
                            }
                        }
                        if (payload_internal_id == self.mSelectedScene) {
                            self.mSelectedScene = i;
                        }
                    }
                }
            }

            //print all of the entities in the scene
            if (is_tree_open) {
                defer imgui.igTreePop();
                var entity_iter = scene_layer.mECSManagerRef.GetAllEntities().iterator();
                while (entity_iter.next()) |entity_id| {
                    const entity = Entity{ .mEntityID = entity_id.key_ptr.*, .mSceneLayerRef = scene_layer };
                    const entity_name = entity.GetName();

                    if (self.mSelectedEntity != null and self.mSelectedEntity.?.mEntityID == entity.mEntityID) {
                        imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Text, selected_text_col);
                    } else {
                        imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Text, other_text_col);
                    }

                    if (imgui.igSelectable_Bool(entity_name.ptr, false, imgui.ImGuiSelectableFlags_None, .{ .x = 0, .y = 0 }) == true) {
                        try ImguiManager.InsertEvent(.{
                            .ET_SelectEntityEvent = .{
                                .SelectedEntity = entity,
                            },
                        });
                    }

                    imgui.igPopStyleColor(1);
                }
            }
        }
    }
    if (imgui.igBeginDragDropTarget() == true) {
        defer imgui.igEndDragDropTarget();
        if (imgui.igAcceptDragDropPayload("IMSCLoad", imgui.ImGuiDragDropFlags_None)) |payload| {
            const path_len = payload.*.DataSize;
            const path = @as([*]const u8, @ptrCast(@alignCast(payload.*.Data)))[0..@intCast(path_len)];
            const new_event = ImguiEvent{
                .ET_OpenSceneEvent = .{
                    .Path = try ImguiManager.EventAllocator().dupe(u8, path),
                },
            };
            try ImguiManager.InsertEvent(new_event);
        }
    }
    if (imgui.igIsItemHovered(imgui.ImGuiHoveredFlags_None) == true and imgui.igIsItemClicked(imgui.ImGuiMouseButton_Right) == true) {
        imgui.igOpenPopup_Str("scene_context", imgui.ImGuiPopupFlags_None);
    }
    if (imgui.igBeginPopup("scene_context", imgui.ImGuiWindowFlags_None) == true) {
        defer imgui.igEndPopup();

        if (imgui.igMenuItem_Bool("New Entity", "", false, true) == true) {
            if (self.mSelectedScene) |selected_scene_id| {
                const new_event = ImguiEvent{
                    .ET_NewEntityEvent = .{
                        .SceneID = selected_scene_id,
                    },
                };
                try ImguiManager.InsertEvent(new_event);
            }
        }

        if (imgui.igBeginMenu("New Scene", true) == true) {
            defer imgui.igEndMenu();
            if (imgui.igMenuItem_Bool("New Game Scene", "", false, true) == true) {
                const new_event = ImguiEvent{
                    .ET_NewSceneEvent = .{
                        .mLayerType = .GameLayer,
                    },
                };
                try ImguiManager.InsertEvent(new_event);
            }
            if (imgui.igMenuItem_Bool("New Overlay Scene", "", false, true) == true) {
                const new_event = ImguiEvent{
                    .ET_NewSceneEvent = .{
                        .mLayerType = .OverlayLayer,
                    },
                };
                try ImguiManager.InsertEvent(new_event);
            }
        }
    }
}

pub fn OnTogglePanelEvent(self: *ScenePanel) void {
    self.mIsVisible = !self.mIsVisible;
}

pub fn OnSelectSceneEvent(self: *ScenePanel, new_scene_id: ?usize) void {
    self.mSelectedScene = new_scene_id;
}

pub fn OnSelectEntityEvent(self: *ScenePanel, new_entity: ?Entity) void {
    self.mSelectedEntity = new_entity;
}

const std = @import("std");
const imgui = @import("../Core/CImports.zig").imgui;
const ImguiEventManager = @import("../Events/ImguiEventManager.zig");
const ImguiEvent = @import("../Events/ImguiEvent.zig").ImguiEvent;
const SceneManager = @import("../Scene/SceneManager.zig");
const EntityType = SceneManager.EntityType;
const SceneType = SceneManager.SceneType;
const ECSManagerScenes = SceneManager.ECSManagerScenes;
const SceneLayer = @import("../Scene/SceneLayer.zig");
const Entity = @import("../GameObjects/Entity.zig");
const SparseSet = @import("../Vendor/zig-sparse-set/src/sparse_set.zig").SparseSet;
const ScenePanel = @This();

const SceneComponents = @import("../Scene/SceneComponents.zig");
const SceneComponent = SceneComponents.SceneComponent;
const SceneStackPos = SceneComponents.StackPosComponent;
const SceneNameComponent = SceneComponents.NameComponent;

const Components = @import("../GameObjects/Components.zig");
const SceneIDComponent = Components.SceneIDComponent;
const NameComponent = Components.NameComponent;

mIsVisible: bool,
mSelectedScene: ?SceneLayer,
mSelectedEntity: ?Entity,

pub fn Init() ScenePanel {
    return ScenePanel{
        .mIsVisible = true,
        .mSelectedScene = null,
        .mSelectedEntity = null,
    };
}

pub fn OnImguiRender(self: *ScenePanel, scene_manager: *SceneManager) !void {
    if (self.mIsVisible == false) return;

    _ = imgui.igBegin("Scenes", null, 0);
    defer imgui.igEnd();

    var available_region: imgui.ImVec2 = undefined;
    imgui.igGetContentRegionAvail(&available_region);

    if (imgui.igBeginChild_Str("SceneChild", available_region, imgui.ImGuiChildFlags_None, imgui.ImGuiWindowFlags_NoMove | imgui.ImGuiWindowFlags_NoScrollbar)) {
        defer imgui.igEndChild();

        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        const name_entities = try scene_manager.mECSManagerGO.GetGroup(.{ .Component = NameComponent }, allocator);

        const stack_pos_scenes = try scene_manager.mECSManagerSC.GetGroup(.{ .Component = SceneStackPos }, allocator);

        std.sort.insertion(SceneType, stack_pos_scenes.items, scene_manager.mECSManagerSC, SceneManager.SortScenesFunc);

        for (stack_pos_scenes.items) |scene_id| {
            const scene_layer = SceneLayer{ .mSceneID = scene_id, .mECSManagerGORef = &scene_manager.mECSManagerGO, .mECSManagerSCRef = &scene_manager.mECSManagerSC };

            const scene_component = scene_layer.GetComponent(SceneComponent);

            const scene_name_component = scene_layer.GetComponent(SceneNameComponent);
            var name_buf: [100]u8 = undefined;
            const scene_name = try std.fmt.bufPrintZ(&name_buf, "{s}", .{scene_name_component.Name.items});

            const selected_text_col = imgui.ImVec4{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 };
            const other_text_col = imgui.ImVec4{ .x = 0.7, .y = 0.7, .z = 0.7, .w = 1.0 };

            const io = imgui.igGetIO();
            const bold_font = io.*.Fonts.*.Fonts.Data[0];

            _ = imgui.igPushID_Str(scene_name.ptr);
            defer imgui.igPopID();

            if (self.mSelectedScene != null and self.mSelectedScene.?.mSceneID == scene_id) {
                imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Text, selected_text_col);
                imgui.igPushFont(bold_font);
            } else {
                imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Text, other_text_col);
            }

            const tree_flags = imgui.ImGuiTreeNodeFlags_OpenOnArrow;
            const is_tree_open = imgui.igTreeNodeEx_Str(scene_name.ptr, tree_flags);
            if (self.mSelectedScene != null and self.mSelectedScene.?.mSceneID == scene_id) {
                imgui.igPopFont();
            }
            imgui.igPopStyleColor(1);

            if (imgui.igIsItemClicked(imgui.ImGuiMouseButton_Left) == true) {
                self.mSelectedScene = scene_layer;
                try ImguiEventManager.Insert(.{
                    .ET_SelectSceneEvent = .{
                        .SelectedScene = scene_layer,
                    },
                });
            }

            const draw_list = imgui.igGetWindowDrawList();
            var min_pos: imgui.ImVec2 = undefined;
            var max_pos: imgui.ImVec2 = undefined;
            imgui.igGetItemRectMin(&min_pos);
            imgui.igGetItemRectMax(&max_pos);
            if (scene_component.mLayerType == .OverlayLayer) {
                imgui.ImDrawList_AddRect(draw_list, min_pos, max_pos, 0xFFEBCE87, 0.0, imgui.ImDrawFlags_None, 1.0);
            } else {
                imgui.ImDrawList_AddRect(draw_list, min_pos, max_pos, 0xFF84A4C4, 0.0, imgui.ImDrawFlags_None, 1.0);
            }

            if (imgui.igBeginDragDropSource(imgui.ImGuiDragDropFlags_None) == true) {
                defer imgui.igEndDragDropSource();
                _ = imgui.igSetDragDropPayload("SceneMove", @ptrCast(&scene_id), @sizeOf(SceneType), imgui.ImGuiCond_Once);
            }

            if (imgui.igBeginDragDropTarget() == true) {
                defer imgui.igEndDragDropTarget();
                if (imgui.igAcceptDragDropPayload("SceneMove", imgui.ImGuiDragDropFlags_None)) |payload| {
                    const payload_scene_id = @as(*SceneType, @ptrCast(@alignCast(payload.*.Data))).*;
                    const new_pos = scene_layer.GetComponent(SceneStackPos).mPosition;
                    const new_event = ImguiEvent{
                        .ET_MoveSceneEvent = .{
                            .SceneID = payload_scene_id,
                            .NewPos = new_pos,
                        },
                    };
                    try ImguiEventManager.Insert(new_event);
                }
            }

            //print all of the entities in the scene
            if (is_tree_open) {
                defer imgui.igTreePop();
                var scene_name_entities = try name_entities.clone();
                defer scene_name_entities.deinit();

                scene_manager.FilterByScene(&scene_name_entities, scene_id);

                for (scene_name_entities.items) |entity_id| {
                    const entity = Entity{ .mEntityID = entity_id, .mECSManagerRef = &scene_manager.mECSManagerGO };
                    const entity_name = entity.GetName();

                    if (self.mSelectedEntity != null and self.mSelectedEntity.?.mEntityID == entity.mEntityID) {
                        imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Text, selected_text_col);
                    } else {
                        imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Text, other_text_col);
                    }
                    defer imgui.igPopStyleColor(1);

                    imgui.igPushID_Int(@intCast(entity_id));
                    defer imgui.igPopID();

                    if (imgui.igSelectable_Bool(entity_name.ptr, false, imgui.ImGuiSelectableFlags_None, .{ .x = 0, .y = 0 }) == true) {
                        try ImguiEventManager.Insert(.{
                            .ET_SelectEntityEvent = .{
                                .SelectedEntity = entity,
                            },
                        });
                    }
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
                    .Path = try ImguiEventManager.EventAllocator().dupe(u8, path),
                },
            };
            try ImguiEventManager.Insert(new_event);
        }
    }
    if (imgui.igIsItemHovered(imgui.ImGuiHoveredFlags_None) == true and imgui.igIsItemClicked(imgui.ImGuiMouseButton_Right) == true) {
        imgui.igOpenPopup_Str("scene_context", imgui.ImGuiPopupFlags_None);
    }
    if (imgui.igBeginPopup("scene_context", imgui.ImGuiWindowFlags_None) == true) {
        defer imgui.igEndPopup();
        if (self.mSelectedScene) |selected_scene_layer| {
            if (imgui.igMenuItem_Bool("New Entity", "", false, true) == true) {
                const new_event = ImguiEvent{
                    .ET_NewEntityEvent = .{
                        .SceneID = selected_scene_layer.mSceneID,
                    },
                };
                try ImguiEventManager.Insert(new_event);
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
                try ImguiEventManager.Insert(new_event);
            }
            if (imgui.igMenuItem_Bool("New Overlay Scene", "", false, true) == true) {
                const new_event = ImguiEvent{
                    .ET_NewSceneEvent = .{
                        .mLayerType = .OverlayLayer,
                    },
                };
                try ImguiEventManager.Insert(new_event);
            }
        }
    }
}

pub fn OnTogglePanelEvent(self: *ScenePanel) void {
    self.mIsVisible = !self.mIsVisible;
}

pub fn OnSelectSceneEvent(self: *ScenePanel, selected_scene: ?SceneLayer) void {
    self.mSelectedScene = selected_scene;
}

pub fn OnSelectEntityEvent(self: *ScenePanel, new_entity: ?Entity) void {
    self.mSelectedEntity = new_entity;
}

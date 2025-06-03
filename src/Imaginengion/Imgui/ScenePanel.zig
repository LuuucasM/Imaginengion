const std = @import("std");
const imgui = @import("../Core/CImports.zig").imgui;
const ImguiEventManager = @import("../Events/ImguiEventManager.zig");
const ImguiEvent = @import("../Events/ImguiEvent.zig").ImguiEvent;
const SceneManager = @import("../Scene/SceneManager.zig");
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

const EntityComponents = @import("../GameObjects/Components.zig");
const EntitySceneComponent = EntityComponents.SceneIDComponent;
const EntityNameComponent = EntityComponents.NameComponent;
const EntityParentComponent = EntityComponents.ParentComponent;
const EntityChildComponent = EntityComponents.ChildComponent;

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

    var already_popup = false;

    //child that is the width of the entire available region is needed so we can drag scenes from the content browser to load the scene
    if (imgui.igBeginChild_Str("SceneChild", available_region, imgui.ImGuiChildFlags_None, imgui.ImGuiWindowFlags_NoMove | imgui.ImGuiWindowFlags_NoScrollbar)) {
        defer imgui.igEndChild();

        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        //getting all the scenes and entities ahead of time to use later
        const name_entities = try scene_manager.mECSManagerGO.GetGroup(.{ .Component = EntityNameComponent }, allocator);

        const stack_pos_scenes = try scene_manager.mECSManagerSC.GetGroup(.{ .Component = SceneStackPos }, allocator);

        //sort the scenes so we can display them in the correct order which matters for handling events and stuff
        std.sort.insertion(SceneType, stack_pos_scenes.items, scene_manager.mECSManagerSC, SceneManager.SortScenesFunc);

        for (stack_pos_scenes.items) |scene_id| {

            //setting up variables to be used later
            const scene_layer = SceneLayer{ .mSceneID = scene_id, .mECSManagerGORef = &scene_manager.mECSManagerGO, .mECSManagerSCRef = &scene_manager.mECSManagerSC };
            const scene_component = scene_layer.GetComponent(SceneComponent);
            const scene_name_component = scene_layer.GetComponent(SceneNameComponent);
            var name_buf: [100]u8 = undefined;
            const scene_name = try std.fmt.bufPrintZ(&name_buf, "{s}", .{scene_name_component.Name.items});

            const selected_text_col = imgui.ImVec4{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 };
            const other_text_col = imgui.ImVec4{ .x = 0.65, .y = 0.65, .z = 0.65, .w = 1.0 };

            const io = imgui.igGetIO();
            const bold_font = io.*.Fonts.*.Fonts.Data[0];

            //push ID so that each scene can have their unique display
            const scene_imgui_id = imgui.igGetID_Str(scene_name.ptr);
            imgui.igPushID_Str(scene_name.ptr);
            defer imgui.igPopID();

            //highlight the text of the selected scene to make it more clear which scene is selected visually
            if (self.mSelectedScene != null and self.mSelectedScene.?.mSceneID == scene_id) {
                imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Text, selected_text_col);
                imgui.igPushFont(bold_font);
            } else {
                imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Text, other_text_col);
            }
            //the node
            const tree_flags = imgui.ImGuiTreeNodeFlags_OpenOnArrow;
            const is_tree_open = imgui.igTreeNodeEx_Str(scene_name.ptr, tree_flags);

            //pop the font from text
            if (self.mSelectedScene) |selected_scene| {
                if (selected_scene.mSceneID == scene_id) {
                    imgui.igPopFont();
                }
            }

            //pop the color for for the tree node
            imgui.igPopStyleColor(1);

            //if item is right clicked open up menu that will allow you to add an entity to the scene
            if (imgui.igBeginPopupContextItem("scene_context", imgui.ImGuiPopupFlags_MouseButtonRight) == true) {
                defer imgui.igEndPopup();
                already_popup = true;

                if (imgui.igMenuItem_Bool("New Entity", "", false, true) == true) {
                    _ = try scene_layer.CreateEntity();
                }
            }

            //if the tree node gets clicked it it becomes the selected scene and also if the selected entity is not in the scene the selected entity becomes null
            if (imgui.igIsItemClicked(imgui.ImGuiMouseButton_Left) == true) {
                try ImguiEventManager.Insert(.{
                    .ET_SelectSceneEvent = .{
                        .SelectedScene = scene_layer,
                    },
                });
                if (self.mSelectedEntity) |selected_entity| {
                    const entity_scene_component = selected_entity.GetComponent(EntitySceneComponent);
                    if (entity_scene_component.SceneID != scene_id) {
                        try ImguiEventManager.Insert(.{
                            .ET_SelectEntityEvent = .{
                                .SelectedEntity = null,
                            },
                        });
                    }
                }
            }

            //add a colored rectangle depending on if its an overlay layer or game layer to differentiate easier
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

            //these are for repositioning and ordering the scenes the user can drag the scenes around to re-order them
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

            //print all of the entities in the scene if the tree is open
            if (is_tree_open) {
                defer imgui.igTreePop();

                var scene_name_entities = try name_entities.clone();
                defer scene_name_entities.deinit();

                scene_manager.FilterEntityByScene(&scene_name_entities, scene_id);

                for (scene_name_entities.items) |entity_id| {
                    const entity = Entity{ .mEntityID = entity_id, .mECSManagerRef = &scene_manager.mECSManagerGO };
                    const entity_name = entity.GetName();

                    //color the selected entity a different color to make it more visual clear what is selected
                    if (self.mSelectedEntity != null and self.mSelectedEntity.?.mEntityID == entity.mEntityID) {
                        imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Text, selected_text_col);
                    } else {
                        imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Text, other_text_col);
                    }

                    imgui.igPushID_Int(@intCast(entity_id));
                    defer imgui.igPopID();
                    //if the entity is selected set it as the new selected entity, and also the scene its in as the new selected scene
                    if (imgui.igSelectable_Bool(entity_name.ptr, false, imgui.ImGuiSelectableFlags_None, .{ .x = 0, .y = 0 }) == true) {
                        try ImguiEventManager.Insert(.{
                            .ET_SelectEntityEvent = .{
                                .SelectedEntity = entity,
                            },
                        });
                        try ImguiEventManager.Insert(.{
                            .ET_SelectSceneEvent = .{
                                .SelectedScene = scene_layer,
                            },
                        });
                    }

                    //pop the color for the entity text
                    imgui.igPopStyleColor(1);

                    //if item is right clicked open up menu that will allow you to add an entity to the entity (hierarchy)
                    if (imgui.igBeginPopupContextItem("entity_context", imgui.ImGuiPopupFlags_MouseButtonRight) == true) {
                        defer imgui.igEndPopup();
                        already_popup = true;

                        if (imgui.igMenuItem_Bool("New Entity", "", false, true) == true) {
                            const new_entity = try scene_layer.CreateEntity();

                            if (entity.HasComponent(EntityParentComponent) == true) {
                                //we already have children entity so we need to iterate to the end of the list
                                const parent_component = entity.GetComponent(EntityParentComponent);
                                var child_entity = Entity{ .mEntityID = parent_component.mFirstChild, .mECSManagerRef = entity.mECSManagerRef };
                                var child_component = child_entity.GetComponent(EntityChildComponent);
                                while (child_component.mNext != Entity.NullEntity) {
                                    child_entity.mEntityID = child_component.mNext;
                                    child_component = child_entity.GetComponent(EntityChildComponent);
                                }

                                //now set the next child to new_entity and add child component to new_entity configured correctly
                                const new_child_component = EntityChildComponent{
                                    .mFirst = child_component.mFirst,
                                    .mNext = Entity.NullEntity,
                                    .mParent = child_component.mParent,
                                    .mPrev = child_entity.mEntityID,
                                };

                                _ = try new_entity.AddComponent(EntityChildComponent, new_child_component);
                            } else {
                                //this is this entities first child so make this entity a parent
                                const new_parent_component = EntityParentComponent{ .mFirstChild = new_entity.mEntityID };
                                _ = try entity.AddComponent(EntityParentComponent, new_parent_component);
                                const new_child_component = EntityChildComponent{
                                    .mFirst = new_entity.mEntityID,
                                    .mNext = Entity.NullEntity,
                                    .mParent = entity.mEntityID,
                                    .mPrev = Entity.NullEntity,
                                };
                                _ = try new_entity.AddComponent(EntityChildComponent, new_child_component);
                            }
                        }
                    }
                }
            }

            //if this scene is double clicked open up its scene specs window
            if (imgui.igIsMouseDoubleClicked_ID(imgui.ImGuiMouseButton_Left, scene_imgui_id) == true) {
                const new_event = ImguiEvent{ .ET_OpenSceneSpecEvent = .{ .mSceneLayer = scene_layer } };
                try ImguiEventManager.Insert(new_event);
            }
        }
    }

    //if tragging a scene onto the entire child window then load the scene
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

    //if right clicking the child window then open up a menu that lets you create a new scene
    if (already_popup == false and imgui.igBeginPopupContextItem("panel_context", imgui.ImGuiPopupFlags_MouseButtonRight) == true) {
        defer imgui.igEndPopup();

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

pub fn OnTogglePanelEvent(self: *ScenePanel) void {
    self.mIsVisible = !self.mIsVisible;
}

pub fn OnSelectSceneEvent(self: *ScenePanel, selected_scene: ?SceneLayer) void {
    self.mSelectedScene = selected_scene;
}

pub fn OnSelectEntityEvent(self: *ScenePanel, new_entity: ?Entity) void {
    self.mSelectedEntity = new_entity;
}

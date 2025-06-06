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
const LayerType = SceneComponent.LayerType;
const SceneStackPos = SceneComponents.StackPosComponent;
const SceneNameComponent = SceneComponents.NameComponent;

const EntityComponents = @import("../GameObjects/Components.zig");
const EntitySceneComponent = EntityComponents.SceneIDComponent;
const EntityNameComponent = EntityComponents.NameComponent;
const EntityParentComponent = EntityComponents.ParentComponent;
const EntityChildComponent = EntityComponents.ChildComponent;

const SCENE_NAME_BUFFER_SIZE = 200;
const ENTITY_NAME_BUFFER_SIZE = 100;

const SELECTED_TEXT_COLOR = imgui.ImVec4{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 };
const NORMAL_TEXT_COLOR = imgui.ImVec4{ .x = 0.65, .y = 0.65, .z = 0.65, .w = 1.0 };
const TREE_FLAGS = imgui.ImGuiTreeNodeFlags_OpenOnArrow;
const OVERLAY_LAYER_COLOR = 0xFFEBCE87;
const GAME_LAYER_COLOR = 0xFF84A4C4;

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
    if (!self.mIsVisible) return;

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

        try self.RenderScenes(scene_manager, allocator, &already_popup);
    }

    try self.HandlePanelContextMenu(already_popup);
    try self.HandlePanelDragDrop();
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

fn RenderScenes(self: *ScenePanel, scene_manager: *SceneManager, allocator: std.mem.Allocator, already_popup: *bool) !void {
    //getting all the scenes and entities ahead of time to use later
    const name_entities = try scene_manager.mECSManagerGO.GetGroup(.{ .Component = EntityNameComponent }, allocator);
    const stack_pos_scenes = try scene_manager.mECSManagerSC.GetGroup(.{ .Component = SceneStackPos }, allocator);

    //sort the scenes so we can display them in the correct order which matters for handling events and stuff
    std.sort.insertion(SceneType, stack_pos_scenes.items, scene_manager.mECSManagerSC, SceneManager.SortScenesFunc);

    for (stack_pos_scenes.items) |scene_id| {
        //setting up variables to be used later
        const scene_layer = SceneLayer{ .mSceneID = scene_id, .mECSManagerGORef = &scene_manager.mECSManagerGO, .mECSManagerSCRef = &scene_manager.mECSManagerSC };

        try self.RenderScene(scene_layer, scene_manager, name_entities, already_popup);
    }
}

fn RenderScene(self: *ScenePanel, scene_layer: SceneLayer, scene_manager: *SceneManager, name_entities: std.ArrayList(Entity.Type), already_popup: *bool) !void {
    const scene_id = scene_layer.mSceneID;
    const scene_component = scene_layer.GetComponent(SceneComponent);
    const scene_name_component = scene_layer.GetComponent(SceneNameComponent);

    var name_buf: [200]u8 = undefined;
    const scene_name = try std.fmt.bufPrintZ(&name_buf, "{s}###{d}", .{ scene_name_component.Name.items, scene_id });

    //push ID so that each scene can have their unique display
    imgui.igPushID_Str(scene_name.ptr);
    defer imgui.igPopID();

    //set text color and font based on if the scene is selected or not
    const is_selected = self.mSelectedScene != null and self.mSelectedScene.?.mSceneID == scene_id;
    self.SetSceneTextStyle(is_selected);
    defer self.PopSceneTextStyle(is_selected);

    //render tree node
    const is_tree_open = imgui.igTreeNodeEx_Str(scene_name.ptr, TREE_FLAGS);

    //if the tree node gets left clicked it becomes the selected scene and also if the selected entity is not in the scene the selected entity becomes null
    if (imgui.igIsItemClicked(imgui.ImGuiMouseButton_Left)) {
        try self.SelectScene(scene_layer);
    }

    //if this scene is double clicked open up its scene specs window
    if (imgui.igIsMouseDoubleClicked_Nil(imgui.ImGuiMouseButton_Left) == true) {
        try ImguiEventManager.Insert(ImguiEvent{ .ET_OpenSceneSpecEvent = .{ .mSceneLayer = scene_layer } });
    }

    //if item is right clicked open up menu that will allow you to add an entity to the scene
    if (!already_popup.* and imgui.igBeginPopupContextItem(scene_name.ptr, imgui.ImGuiPopupFlags_MouseButtonRight)) {
        defer imgui.igEndPopup();
        already_popup.* = true;

        if (imgui.igMenuItem_Bool("New Entity", "", false, true)) {
            _ = try scene_layer.CreateEntity();
        }
    }

    self.DrawSceneBorder(scene_component.mLayerType);

    try self.HandleSceneDragDrop(scene_layer);

    if (is_tree_open) {
        defer imgui.igTreePop();
        try self.RenderSceneEntities(scene_manager, name_entities, scene_layer, already_popup);
    }
}

fn SetSceneTextStyle(_: *ScenePanel, is_selected: bool) void {
    if (is_selected) {
        imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Text, SELECTED_TEXT_COLOR);
        const io = imgui.igGetIO();
        const bold_font = io.*.Fonts.*.Fonts.Data[0];
        imgui.igPushFont(bold_font);
    } else {
        imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Text, NORMAL_TEXT_COLOR);
    }
}

fn PopSceneTextStyle(_: *ScenePanel, is_selected: bool) void {
    if (is_selected) {
        imgui.igPopFont();
    }
    imgui.igPopStyleColor(1);
}

fn SelectScene(self: *ScenePanel, scene_layer: SceneLayer) !void {
    const scene_id = scene_layer.mSceneID;

    try ImguiEventManager.Insert(.{ .ET_SelectSceneEvent = .{ .SelectedScene = scene_layer } });

    if (self.mSelectedEntity) |selected_entity| {
        const entity_scene_component = selected_entity.GetComponent(EntitySceneComponent);
        if (entity_scene_component.SceneID != scene_id) {
            try ImguiEventManager.Insert(.{ .ET_SelectEntityEvent = .{ .SelectedEntity = null } });
        }
    }
}

fn DrawSceneBorder(_: *ScenePanel, layer_type: LayerType) void {
    const draw_list = imgui.igGetWindowDrawList();
    var min_pos: imgui.ImVec2 = undefined;
    var max_pos: imgui.ImVec2 = undefined;
    imgui.igGetItemRectMin(&min_pos);
    imgui.igGetItemRectMax(&max_pos);

    const color: u32 = switch (layer_type) {
        .OverlayLayer => OVERLAY_LAYER_COLOR,
        else => GAME_LAYER_COLOR,
    };

    imgui.ImDrawList_AddRect(draw_list, min_pos, max_pos, color, 0.0, imgui.ImDrawFlags_None, 1.0);
}

fn HandleSceneDragDrop(_: *ScenePanel, scene_layer: SceneLayer) !void {
    //these are for repositioning and ordering the scenes the user can drag the scenes around to re-order them
    if (imgui.igBeginDragDropSource(imgui.ImGuiDragDropFlags_None) == true) {
        defer imgui.igEndDragDropSource();
        _ = imgui.igSetDragDropPayload("SceneMove", @ptrCast(&scene_layer.mSceneID), @sizeOf(SceneType), imgui.ImGuiCond_Once);
    }

    if (imgui.igBeginDragDropTarget() == true) {
        defer imgui.igEndDragDropTarget();
        if (imgui.igAcceptDragDropPayload("SceneMove", imgui.ImGuiDragDropFlags_None)) |payload| {
            const payload_scene_id = @as(*SceneType, @ptrCast(@alignCast(payload.*.Data))).*;
            const new_pos = scene_layer.GetComponent(SceneStackPos).mPosition;
            try ImguiEventManager.Insert(ImguiEvent{
                .ET_MoveSceneEvent = .{
                    .SceneID = payload_scene_id,
                    .NewPos = new_pos,
                },
            });
        }
    }
}

fn RenderSceneEntities(self: *ScenePanel, scene_manager: *SceneManager, name_entities: std.ArrayList(Entity.Type), scene_layer: SceneLayer, already_popup: *bool) !void {
    var scene_name_entities = try name_entities.clone();
    defer scene_name_entities.deinit();

    scene_manager.FilterEntityByScene(&scene_name_entities, scene_layer.mSceneID);

    for (scene_name_entities.items) |entity_id| {
        const entity = Entity{ .mEntityID = entity_id, .mECSManagerRef = &scene_manager.mECSManagerGO };
        try self.RenderSceneEntitiy(entity, scene_layer, already_popup);
    }
}

fn RenderSceneEntitiy(self: *ScenePanel, entity: Entity, scene_layer: SceneLayer, already_popup: *bool) !void {
    // Skip child entities (they're rendered as part of their parent's hierarchy)
    if (entity.HasComponent(EntityChildComponent)) return;
    try self.RenderEntity(entity, scene_layer, already_popup);
}

fn RenderEntity(self: *ScenePanel, entity: Entity, scene_layer: SceneLayer, already_popup: *bool) !void {
    var name_buf: [ENTITY_NAME_BUFFER_SIZE]u8 = undefined;
    const entity_name = try std.fmt.bufPrintZ(&name_buf, "{s}###{d}", .{ entity.GetName(), entity.mEntityID });

    // Set text color based on selection
    const is_selected = self.mSelectedEntity != null and self.mSelectedEntity.?.mEntityID == entity.mEntityID;
    const text_color = if (is_selected) SELECTED_TEXT_COLOR else NORMAL_TEXT_COLOR;
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Text, text_color);
    defer imgui.igPopStyleColor(1);

    imgui.igPushID_Int(@intCast(entity.mEntityID));
    defer imgui.igPopID();

    if (entity.HasComponent(EntityParentComponent)) {
        try self.RenderParentEntity(entity, entity_name, scene_layer, already_popup);
    } else {
        try self.RenderLeafEntity(entity, entity_name, scene_layer, already_popup);
    }
}

fn RenderParentEntity(self: *ScenePanel, entity: Entity, entity_name: [*:0]const u8, scene_layer: SceneLayer, already_popup: *bool) !void {
    const is_entity_tree_open = imgui.igTreeNodeEx_Str(entity_name, TREE_FLAGS);

    //if the tree node gets left clicked it becomes the selected scene and also if the selected entity is not in the scene the selected entity becomes null
    if (imgui.igIsItemClicked(imgui.ImGuiMouseButton_Left)) {
        try self.SelectEntity(entity, scene_layer);
    }

    try self.HandleEntityContextMenu(entity, entity_name, scene_layer, already_popup);

    if (is_entity_tree_open) {
        defer imgui.igTreePop();
        try self.RenderChildEntities(entity, scene_layer, already_popup);
    }
}

fn RenderLeafEntity(self: *ScenePanel, entity: Entity, entity_name: [*:0]const u8, scene_layer: SceneLayer, already_popup: *bool) !void {
    if (imgui.igSelectable_Bool(entity_name, false, imgui.ImGuiSelectableFlags_None, .{ .x = 0, .y = 0 })) {
        try self.SelectEntity(entity, scene_layer);
    }

    try self.HandleEntityContextMenu(entity, entity_name, scene_layer, already_popup);
}

fn SelectEntity(_: *ScenePanel, entity: Entity, scene_layer: SceneLayer) !void {
    try ImguiEventManager.Insert(.{ .ET_SelectEntityEvent = .{ .SelectedEntity = entity } });
    try ImguiEventManager.Insert(.{ .ET_SelectSceneEvent = .{ .SelectedScene = scene_layer } });
}

fn HandleEntityContextMenu(self: *ScenePanel, entity: Entity, entity_name: [*:0]const u8, scene_layer: SceneLayer, already_popup: *bool) !void {
    //if item is right clicked open up menu that will allow you to add an entity to the scene
    if (!already_popup.* and imgui.igBeginPopupContextItem(entity_name, imgui.ImGuiPopupFlags_MouseButtonRight)) {
        defer imgui.igEndPopup();
        already_popup.* = true;

        if (imgui.igMenuItem_Bool("New Entity", "", false, true)) {
            try self.AddChildEntity(entity, scene_layer);
        }
    }
}

fn AddChildEntity(self: *ScenePanel, parent_entity: Entity, scene_layer: SceneLayer) !void {
    const new_entity = try scene_layer.CreateEntity();

    if (parent_entity.HasComponent(EntityParentComponent)) {
        try self.AddToExistingChildren(parent_entity, new_entity);
    } else {
        try self.MakeEntityParent(parent_entity, new_entity);
    }
}

fn AddToExistingChildren(_: *ScenePanel, parent_entity: Entity, new_entity: Entity) !void {
    const parent_component = parent_entity.GetComponent(EntityParentComponent);
    var child_entity = Entity{ .mEntityID = parent_component.mFirstChild, .mECSManagerRef = parent_entity.mECSManagerRef };

    // Find the last child in the list
    var child_component = child_entity.GetComponent(EntityChildComponent);
    while (child_component.mNext != Entity.NullEntity) {
        child_entity.mEntityID = child_component.mNext;
        child_component = child_entity.GetComponent(EntityChildComponent);
    }

    // Add new entity to end of list
    const new_child_component = EntityChildComponent{
        .mFirst = child_component.mFirst,
        .mNext = Entity.NullEntity,
        .mParent = child_component.mParent,
        .mPrev = child_entity.mEntityID,
    };

    _ = try new_entity.AddComponent(EntityChildComponent, new_child_component);

    //set the new child component.mNext to be the new child
    child_component.mNext = new_entity.mEntityID;
}

fn MakeEntityParent(_: *ScenePanel, parent_entity: Entity, new_entity: Entity) !void {
    const new_parent_component = EntityParentComponent{ .mFirstChild = new_entity.mEntityID };
    _ = try parent_entity.AddComponent(EntityParentComponent, new_parent_component);

    const new_child_component = EntityChildComponent{
        .mFirst = new_entity.mEntityID,
        .mNext = Entity.NullEntity,
        .mParent = parent_entity.mEntityID,
        .mPrev = Entity.NullEntity,
    };
    _ = try new_entity.AddComponent(EntityChildComponent, new_child_component);
}

fn RenderChildEntities(self: *ScenePanel, parent_entity: Entity, scene_layer: SceneLayer, already_popup: *bool) anyerror!void {
    const entity_parent_component = parent_entity.GetComponent(EntityParentComponent);
    var curr_id = entity_parent_component.mFirstChild;

    while (curr_id != Entity.NullEntity) {
        const child_entity = Entity{ .mEntityID = curr_id, .mECSManagerRef = parent_entity.mECSManagerRef };
        try self.RenderEntity(child_entity, scene_layer, already_popup);

        const child_component = child_entity.GetComponent(EntityChildComponent);
        curr_id = child_component.mNext;
    }
}

fn HandlePanelDragDrop(_: *ScenePanel) !void {
    if (imgui.igBeginDragDropTarget()) {
        defer imgui.igEndDragDropTarget();
        if (imgui.igAcceptDragDropPayload("IMSCLoad", imgui.ImGuiDragDropFlags_None)) |payload| {
            const path_len = payload.*.DataSize;
            const path = @as([*]const u8, @ptrCast(@alignCast(payload.*.Data)))[0..@intCast(path_len)];
            try ImguiEventManager.Insert(.{
                .ET_OpenSceneEvent = .{
                    .Path = try ImguiEventManager.EventAllocator().dupe(u8, path),
                },
            });
        }
    }
}

fn HandlePanelContextMenu(_: *ScenePanel, already_popup: bool) !void {
    if (!already_popup and imgui.igBeginPopupContextItem("panel_context", imgui.ImGuiPopupFlags_MouseButtonRight)) {
        defer imgui.igEndPopup();

        if (imgui.igMenuItem_Bool("New Game Scene", "", false, true)) {
            try ImguiEventManager.Insert(.{ .ET_NewSceneEvent = .{ .mLayerType = .GameLayer } });
        }
        if (imgui.igMenuItem_Bool("New Overlay Scene", "", false, true)) {
            try ImguiEventManager.Insert(.{ .ET_NewSceneEvent = .{ .mLayerType = .OverlayLayer } });
        }
    }
}

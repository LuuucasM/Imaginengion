const std = @import("std");
const imgui = @import("../Core/CImports.zig").imgui;
const ImguiEvent = @import("../Events/ImguiEvent.zig").ImguiEvent;
const SceneManager = @import("../Scene/SceneManager.zig");
const SceneType = SceneLayer.Type;
const ECSManagerScenes = SceneManager.ECSManagerScenes;
const SceneLayer = @import("../Scene/SceneLayer.zig");
const Entity = @import("../GameObjects/Entity.zig");
const SparseSet = @import("../Vendor/zig-sparse-set/src/sparse_set.zig").SparseSet;
const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;
const GameObjectUtils = @import("../GameObjects/GameObjectUtils.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const ScenePanel = @This();

const SceneComponents = @import("../Scene/SceneComponents.zig");
const SceneComponent = SceneComponents.SceneComponent;
const LayerType = SceneComponent.LayerType;
const SceneStackPos = SceneComponents.StackPosComponent;
const SceneNameComponent = SceneComponents.NameComponent;

const EntityComponents = @import("../GameObjects/Components.zig");
const EntitySceneComponent = EntityComponents.SceneIDComponent;
const EntityNameComponent = EntityComponents.NameComponent;
const EntityParentComponent = @import("../ECS/Components.zig").ParentComponent(Entity.Type);
const EntityChildComponent = @import("../ECS/Components.zig").ChildComponent(Entity.Type);

const Tracy = @import("../Core/Tracy.zig");

const SCENE_NAME_BUFFER_SIZE = 200;
const ENTITY_NAME_BUFFER_SIZE = 100;

const SELECTED_TEXT_COLOR = imgui.ImVec4{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 };
const NORMAL_TEXT_COLOR = imgui.ImVec4{ .x = 0.65, .y = 0.65, .z = 0.65, .w = 1.0 };
const TREE_FLAGS = imgui.ImGuiTreeNodeFlags_OpenOnArrow;
const OVERLAY_LAYER_COLOR = 0xFFEBCE87;
const GAME_LAYER_COLOR = 0xFF84A4C4;

mIsVisible: bool = true,
mSelectedScene: ?SceneLayer = null,
mSelectedEntity: ?Entity = null,

pub fn Init(self: ScenePanel) void {
    _ = self;
}

pub fn OnImguiRender(self: *ScenePanel, engine_context: *EngineContext, scene_manager: *SceneManager) !void {
    const zone = Tracy.ZoneInit("ScenePanel OIR", @src());
    defer zone.Deinit();

    if (!self.mIsVisible) return;

    _ = imgui.igBegin("Scenes", null, 0);
    defer imgui.igEnd();

    var available_region: imgui.ImVec2 = undefined;
    imgui.igGetContentRegionAvail(&available_region);

    var already_popup = false;

    //child that is the width of the entire available region is needed so we can drag scenes from the content browser to load the scene
    if (imgui.igBeginChild_Str("SceneChild", available_region, imgui.ImGuiChildFlags_None, imgui.ImGuiWindowFlags_NoMove | imgui.ImGuiWindowFlags_NoScrollbar)) {
        defer imgui.igEndChild();

        try self.RenderScenes(engine_context, scene_manager, &already_popup);
    }
    try self.HandlePanelContextMenu(engine_context, already_popup);
    try self.HandlePanelDragDrop(engine_context);
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

pub fn OnDeleteEntity(self: *ScenePanel, delete_entity: Entity) void {
    if (self.mSelectedEntity) |selected_entity| {
        if (selected_entity.mEntityID == delete_entity.mEntityID) {
            self.mSelectedEntity = null;
        }
    }
}

pub fn OnDeleteScene(self: *ScenePanel, delete_scene: SceneLayer) void {
    if (self.mSelectedScene) |selected_scene| {
        if (selected_scene.mSceneID == delete_scene.mSceneID) {
            self.mSelectedScene = null;
        }
    }
}

fn RenderScenes(self: *ScenePanel, engine_context: *EngineContext, scene_manager: *SceneManager, already_popup: *bool) !void {
    const frame_allocator = engine_context.mFrameAllocator;
    //getting all the scenes and entities ahead of time to use later
    const name_entities = try scene_manager.mECSManagerGO.GetGroup(frame_allocator, GroupQuery{ .Not = .{
        .mFirst = GroupQuery{ .Component = EntityNameComponent },
        .mSecond = GroupQuery{ .Component = EntityChildComponent },
    } });
    const stack_pos_scenes = try scene_manager.mECSManagerSC.GetGroup(frame_allocator, .{ .Component = SceneStackPos });

    //sort the scenes so we can display them in the correct order which matters for handling events and stuff
    std.sort.insertion(SceneType, stack_pos_scenes.items, scene_manager.mECSManagerSC, SceneManager.SortScenesFunc);

    for (stack_pos_scenes.items) |scene_id| {
        //setting up variables to be used later
        const scene_layer = SceneLayer{ .mSceneID = scene_id, .mECSManagerGORef = &scene_manager.mECSManagerGO, .mECSManagerSCRef = &scene_manager.mECSManagerSC };

        try self.RenderScene(engine_context, scene_layer, scene_manager, name_entities, already_popup);
    }
}

fn RenderScene(self: *ScenePanel, engine_context: *EngineContext, scene_layer: SceneLayer, scene_manager: *SceneManager, name_entities: std.ArrayList(Entity.Type), already_popup: *bool) !void {
    const frame_allocator = engine_context.mFrameAllocator;
    const scene_id = scene_layer.mSceneID;
    const scene_component = scene_layer.GetComponent(SceneComponent).?;
    const scene_name_component = scene_layer.GetComponent(SceneNameComponent).?;

    const scene_name = try std.fmt.allocPrintSentinel(frame_allocator, "{s}###{d}", .{ scene_name_component.mName.items, scene_id }, 0);

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
        try self.SelectScene(engine_context, scene_layer);
    }

    //if this scene is double clicked open up its scene specs window
    if (imgui.igIsItemHovered(imgui.ImGuiHoveredFlags_None) and imgui.igIsMouseDoubleClicked_Nil(imgui.ImGuiMouseButton_Left) == true) {
        try engine_context.mImguiEventManager.Insert(engine_context.mEngineAllocator, ImguiEvent{ .ET_OpenSceneSpecEvent = .{ .mSceneLayer = scene_layer } });
    }

    try self.HandleScenePopupContext(engine_context, scene_layer, scene_name, already_popup);

    self.DrawSceneBorder(scene_component.mLayerType);

    try self.HandleSceneDragDrop(engine_context, scene_layer);

    if (is_tree_open) {
        defer imgui.igTreePop();
        try self.RenderSceneEntities(engine_context, scene_manager, name_entities, scene_layer, already_popup);
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

fn SelectScene(self: *ScenePanel, engine_context: *EngineContext, scene_layer: SceneLayer) !void {
    const scene_id = scene_layer.mSceneID;

    try engine_context.mImguiEventManager.Insert(engine_context.mEngineAllocator, .{ .ET_SelectSceneEvent = .{ .SelectedScene = scene_layer } });

    if (self.mSelectedEntity) |selected_entity| {
        const entity_scene_component = selected_entity.GetComponent(EntitySceneComponent).?;
        if (entity_scene_component.SceneID != scene_id) {
            try engine_context.mImguiEventManager.Insert(engine_context.mEngineAllocator, .{ .ET_SelectEntityEvent = .{ .SelectedEntity = null } });
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

fn HandleScenePopupContext(_: *ScenePanel, engine_context: *EngineContext, scene_layer: SceneLayer, scene_name: []const u8, already_popup: *bool) !void {
    //if item is right clicked open up menu that will allow you to add an entity to the scene
    if (!already_popup.* and imgui.igBeginPopupContextItem(scene_name.ptr, imgui.ImGuiPopupFlags_MouseButtonRight)) {
        defer imgui.igEndPopup();
        already_popup.* = true;

        if (imgui.igMenuItem_Bool("New Entity", "", false, true)) {
            _ = try scene_layer.CreateEntity(engine_context.mEngineAllocator);
        }

        if (imgui.igMenuItem_Bool("Delete Scene", "", false, true)) {
            try scene_layer.Delete(engine_context);
        }
    }
}

fn HandleSceneDragDrop(_: *ScenePanel, engine_context: *EngineContext, scene_layer: SceneLayer) !void {
    //these are for repositioning and ordering the scenes the user can drag the scenes around to re-order them
    if (imgui.igBeginDragDropSource(imgui.ImGuiDragDropFlags_None) == true) {
        defer imgui.igEndDragDropSource();
        _ = imgui.igSetDragDropPayload("SceneMove", @ptrCast(&scene_layer.mSceneID), @sizeOf(SceneType), imgui.ImGuiCond_Once);
    }

    if (imgui.igBeginDragDropTarget() == true) {
        defer imgui.igEndDragDropTarget();
        if (imgui.igAcceptDragDropPayload("SceneMove", imgui.ImGuiDragDropFlags_None)) |payload| {
            const payload_scene_id = @as(*SceneType, @ptrCast(@alignCast(payload.*.Data))).*;
            const new_pos = scene_layer.GetComponent(SceneStackPos).?.mPosition;
            try engine_context.mImguiEventManager.Insert(engine_context.mEngineAllocator, ImguiEvent{
                .ET_MoveSceneEvent = .{
                    .SceneID = payload_scene_id,
                    .NewPos = new_pos,
                },
            });
        }
    }
}

fn RenderSceneEntities(self: *ScenePanel, engine_context: *EngineContext, scene_manager: *SceneManager, name_entities: std.ArrayList(Entity.Type), scene_layer: SceneLayer, already_popup: *bool) !void {
    const frame_allocator = engine_context.mFrameAllocator;

    var scene_name_entities = try name_entities.clone(frame_allocator);
    defer scene_name_entities.deinit(frame_allocator);

    scene_manager.FilterEntityByScene(frame_allocator, &scene_name_entities, scene_layer.mSceneID);

    for (scene_name_entities.items) |entity_id| {
        const entity = Entity{ .mEntityID = entity_id, .mECSManagerRef = &scene_manager.mECSManagerGO };
        try self.RenderEntity(engine_context, entity, scene_layer, already_popup);
    }
}

fn RenderEntity(self: *ScenePanel, engine_context: *EngineContext, entity: Entity, scene_layer: SceneLayer, already_popup: *bool) !void {
    const frame_allocator = engine_context.mFrameAllocator;
    const entity_name = try std.fmt.allocPrintSentinel(frame_allocator, "{s}###{d}", .{ entity.GetName(), entity.mEntityID }, 0);

    // Set text color based on selection
    const is_selected = self.mSelectedEntity != null and self.mSelectedEntity.?.mEntityID == entity.mEntityID;
    const text_color = if (is_selected) SELECTED_TEXT_COLOR else NORMAL_TEXT_COLOR;
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Text, text_color);
    defer imgui.igPopStyleColor(1);

    imgui.igPushID_Int(@intCast(entity.mEntityID));
    defer imgui.igPopID();

    if (entity.HasComponent(EntityParentComponent)) {
        try self.RenderParentEntity(engine_context, entity, entity_name, scene_layer, already_popup);
    } else {
        try self.RenderLeafEntity(engine_context, entity, entity_name, scene_layer, already_popup);
    }
}

fn RenderParentEntity(self: *ScenePanel, engine_context: *EngineContext, entity: Entity, entity_name: [*:0]const u8, scene_layer: SceneLayer, already_popup: *bool) !void {
    const is_entity_tree_open = imgui.igTreeNodeEx_Str(entity_name, TREE_FLAGS);

    //if the tree node gets left clicked it becomes the selected scene and also if the selected entity is not in the scene the selected entity becomes null
    if (imgui.igIsItemClicked(imgui.ImGuiMouseButton_Left)) {
        try self.SelectEntity(engine_context, entity, scene_layer);
    }

    try self.HandleEntityContextMenu(engine_context, entity, entity_name, scene_layer, already_popup);

    if (is_entity_tree_open) {
        defer imgui.igTreePop();
        try self.RenderChildEntities(engine_context, entity, scene_layer, already_popup);
    }
}

fn RenderLeafEntity(self: *ScenePanel, engine_context: *EngineContext, entity: Entity, entity_name: [*:0]const u8, scene_layer: SceneLayer, already_popup: *bool) !void {
    if (imgui.igSelectable_Bool(entity_name, false, imgui.ImGuiSelectableFlags_None, .{ .x = 0, .y = 0 })) {
        try self.SelectEntity(engine_context, entity, scene_layer);
    }

    try self.HandleEntityContextMenu(engine_context, entity, entity_name, scene_layer, already_popup);
}

fn SelectEntity(_: *ScenePanel, engine_context: *EngineContext, entity: Entity, scene_layer: SceneLayer) !void {
    try engine_context.mImguiEventManager.Insert(engine_context.mEngineAllocator, .{ .ET_SelectEntityEvent = .{ .SelectedEntity = entity } });
    try engine_context.mImguiEventManager.Insert(engine_context.mEngineAllocator, .{ .ET_SelectSceneEvent = .{ .SelectedScene = scene_layer } });
}

fn HandleEntityContextMenu(_: *ScenePanel, engine_context: *EngineContext, entity: Entity, entity_name: [*:0]const u8, scene_layer: SceneLayer, already_popup: *bool) !void {
    //if item is right clicked open up menu that will allow you to add an entity to the scene
    if (!already_popup.* and imgui.igBeginPopupContextItem(entity_name, imgui.ImGuiPopupFlags_MouseButtonRight)) {
        defer imgui.igEndPopup();
        already_popup.* = true;

        if (imgui.igMenuItem_Bool("New Entity", "", false, true)) {
            _ = try scene_layer.AddChildEntity(engine_context.mEngineAllocator, entity);
        }

        if (imgui.igMenuItem_Bool("Delete Entity", "", false, true)) {
            try entity.Delete(engine_context);
        }
    }
}
fn RenderChildEntities(self: *ScenePanel, engine_context: *EngineContext, parent_entity: Entity, scene_layer: SceneLayer, already_popup: *bool) anyerror!void {
    if (parent_entity.GetComponent(EntityParentComponent)) |parent_component| {
        var curr_id = parent_component.mFirstChild;

        while (true) : (if (curr_id == parent_component.mFirstChild) break) {
            const child_entity = Entity{ .mEntityID = curr_id, .mECSManagerRef = parent_entity.mECSManagerRef };

            try self.RenderEntity(engine_context, child_entity, scene_layer, already_popup);

            const child_component = child_entity.GetComponent(EntityChildComponent).?;
            curr_id = child_component.mNext;
        }
    }
}

fn HandlePanelDragDrop(_: *ScenePanel, engine_context: *EngineContext) !void {
    if (imgui.igBeginDragDropTarget()) {
        defer imgui.igEndDragDropTarget();
        if (imgui.igAcceptDragDropPayload("IMSCLoad", imgui.ImGuiDragDropFlags_None)) |payload| {
            const path_len = payload.*.DataSize;
            const path = @as([*]const u8, @ptrCast(@alignCast(payload.*.Data)))[0..@intCast(path_len)];
            try engine_context.mImguiEventManager.Insert(engine_context.mEngineAllocator, .{
                .ET_OpenSceneEvent = .{
                    .mAbsPath = try engine_context.mEngineAllocator.dupe(u8, path),
                    .mAllocator = engine_context.mEngineAllocator,
                },
            });
        }
    }
}

fn HandlePanelContextMenu(_: *ScenePanel, engine_context: *EngineContext, already_popup: bool) !void {
    if (!already_popup and imgui.igBeginPopupContextItem("panel_context", imgui.ImGuiPopupFlags_MouseButtonRight)) {
        defer imgui.igEndPopup();

        if (imgui.igMenuItem_Bool("New Game Scene", "", false, true)) {
            try engine_context.mImguiEventManager.Insert(engine_context.mEngineAllocator, .{ .ET_NewSceneEvent = .{ .mLayerType = .GameLayer } });
        }
        if (imgui.igMenuItem_Bool("New Overlay Scene", "", false, true)) {
            try engine_context.mImguiEventManager.Insert(engine_context.mEngineAllocator, .{ .ET_NewSceneEvent = .{ .mLayerType = .OverlayLayer } });
        }
    }
}

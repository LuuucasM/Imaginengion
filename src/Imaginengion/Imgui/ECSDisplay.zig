const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const FileMetaData = @import("../Assets/Assets/FileMetaData.zig");
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const SceneManager = @import("../Scene/SceneManager.zig");
const EntityTagComponent = @import("../ECS/Components.zig").EntityTagComponent;
const Entity = @import("../GameObjects/Entity.zig");
const SceneLayer = @import("../Scene/SceneLayer.zig");
const Player = @import("../Players/Player.zig");
const GameMode = @import("../GameModes/GameMode.zig");
const ECSDisplayPanel = @This();

const SCENE_NAME_BUFFER_SIZE = 200;
const ENTITY_NAME_BUFFER_SIZE = 100;

const SELECTED_TEXT_COLOR = imgui.ImVec4{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 };
const NORMAL_TEXT_COLOR = imgui.ImVec4{ .x = 0.65, .y = 0.65, .z = 0.65, .w = 1.0 };
const TREE_FLAGS = imgui.ImGuiTreeNodeFlags_OpenOnArrow;
const OVERLAY_LAYER_COLOR = 0xFFEBCE87;
const GAME_LAYER_COLOR = 0xFF84A4C4;

_P_Open: bool = true,

pub fn Init(self: ECSDisplayPanel) void {
    _ = self;
}

pub fn OnImguiRender(self: ECSDisplayPanel, engine_context: *EngineContext, comptime world_type: EngineContext.WorldType, comptime ecs_type: SceneManager.ECSType) !void {
    const zone = Tracy.ZoneInit("AssetHandle OIR", @src());
    defer zone.Deinit();

    if (self._P_Open == false) return;

    const frame_allocator = engine_context.FrameAllocator();

    const scene_manager = switch (world_type) {
        .Game => &engine_context.mGameWorld,
        .Simulate => &engine_context.mSimulateWorld,
        .Editor => &engine_context.mEditorWorld,
    };

    const window_name = try std.fmt.allocPrintSentinel(frame_allocator, "{s} - {s}", .{ @tagName(world_type), @tagName(ecs_type) }, 0);

    _ = imgui.igBegin(window_name.ptr, null, 0);
    defer imgui.igEnd();

    var available_region: imgui.ImVec2 = undefined;
    imgui.igGetContentRegionAvail(&available_region);

    var already_popup = false;

    //child that is the width of the entire available region is needed so we can drag scenes from the content browser to load the scene
    if (imgui.igBeginChild_Str("SceneChild", available_region, imgui.ImGuiChildFlags_None, imgui.ImGuiWindowFlags_NoMove | imgui.ImGuiWindowFlags_NoScrollbar)) {
        defer imgui.igEndChild();

        switch (ecs_type) {
            .GameObj => RenderObjects(Entity, engine_context, scene_manager, &already_popup),
            .Scenes => RenderObjects(SceneLayer, engine_context, scene_manager, &already_popup),
            .Players => RenderObjects(Player, engine_context, scene_manager, &already_popup),
            .GameModes => RenderObjects(GameMode, engine_context, scene_manager, &already_popup),
        }
    }
}

pub fn OnTogglePanelEvent(self: *ECSDisplayPanel) void {
    self._P_Open = !self._P_Open;
}

fn RenderObjects(comptime ObjectType: type, engine_context: *EngineContext, scene_manager: *SceneManager, already_popup: *bool) !void {
    const Traits = ObjectTraits(ObjectType);
    const frame_allocator = engine_context.FrameAllocator();

    const objects_list = try Traits.GetGroupFn(scene_manager, frame_allocator, .{ .Not = .{ .mFirst = EntityTagComponent, .mSecond = Traits.ChildComponent } });
    for (objects_list.items) |object_id| {
        const object = Traits.GetObject(object_id, scene_manager);
        RenderObject(ObjectType, engine_context, object, already_popup);
    }
}

fn RenderObject(comptime ObjectType: type, engine_context: *EngineContext, object: ObjectType, already_popup: *bool) !void {
    const Traits = ObjectTraits(ObjectType);
    if (object.HasComponent(Traits.ParentComponent)) {
        try RenderParentObject(ObjectType, engine_context, object, already_popup);
    } else {
        try RenderLeafObject(ObjectType, engine_context, object, already_popup);
    }
}

fn RenderParentObject(comptime ObjectType: type, engine_context: *EngineContext, object: ObjectType, already_popup: *bool) !void {
    const Traits = ObjectTraits(ObjectType);
    const frame_allocator = engine_context.FrameAllocator();

    const object_name = try std.fmt.allocPrintSentinel(frame_allocator, "{s}###{d}", .{ object.GetName(), Traits.ID(object) }, 0);

    const is_entity_tree_open = imgui.igTreeNodeEx_Str(object_name, TREE_FLAGS);

    //if the tree node gets left clicked it becomes the selected scene and also if the selected entity is not in the scene the selected entity becomes null
    if (imgui.igIsItemClicked(imgui.ImGuiMouseButton_Left)) {
        //TODO: need to rework how selection works so holdon there
        //try SelectEntity(engine_context, entity, scene_layer);
    }

    try HandleObjectContextMenu(ObjectType, engine_context, object, object_name, already_popup);

    if (is_entity_tree_open) {
        defer imgui.igTreePop();
        try RenderChildObjects(ObjectType, engine_context, object, already_popup);
    }
}

fn RenderLeafObject(comptime ObjectType: type, engine_context: *EngineContext, object: ObjectType, already_popup: *bool) !void {
    const Traits = ObjectTraits(ObjectType);
    const frame_allocator = engine_context.FrameAllocator();

    const object_name = try std.fmt.allocPrintSentinel(frame_allocator, "{s}###{d}", .{ object.GetName(), Traits.ID(object) }, 0);

    if (imgui.igSelectable_Bool(object_name, false, imgui.ImGuiSelectableFlags_None, .{ .x = 0, .y = 0 })) {
        //TODO: need to rework new selection system
        //try SelectEntity(engine_context, entity, scene_layer);
    }

    try HandleObjectContextMenu(ObjectType, engine_context, object, object_name, already_popup);
}

fn RenderChildObjects(comptime ObjectType: type, engine_context: *EngineContext, parent_object: ObjectType, already_popup: *bool) !void {
    if (parent_object.GetIterator(.Child)) |iter| {
        while (iter.next()) |child_object| {
            try RenderObject(ObjectType, engine_context, child_object, already_popup);
        }
    }
}

fn HandleObjectContextMenu(comptime ObjectType: type, engine_context: *EngineContext, object: ObjectType, object_name: [*:0]const u8, already_popup: *bool) !void {
    const Trait = ObjectTraits(ObjectType);

    Trait.HandleDragDropSource(object);

    if (!already_popup.* and imgui.igBeginPopupContextItem(object_name, imgui.ImGuiPopupFlags_MouseButtonRight)) {
        defer imgui.igEndPopup();
        already_popup.* = true;

        if (imgui.igMenuItem_Bool("New Child", "", false, true)) {
            _ = try object.CreateChild(engine_context, .Entity, .{});
        }

        if (imgui.igMenuItem_Bool("Delete Object", "", false, true)) {
            try object.Delete(engine_context);
        }
    }
}

fn ObjectTraits(comptime T: type) type {
    if (T == Entity) {
        return struct {
            const ParentComponent = SceneManager.ECSManagerGameObj.ParentComponent;
            const ChildComponent = SceneManager.ECSManagerGameObj.ChildComponent;
            const GetGroupFn = SceneManager.GetEntityGroup;
            pub fn ID(entity: Entity) u64 {
                return @intCast(entity.mEntityID);
            }
            pub fn GetObject(entity_id: u64, scene_manager: *SceneManager) Entity {
                return scene_manager.GetEntity(@intCast(entity_id));
            }
            pub fn HandleDragDropSource(entity: Entity) void {
                if (imgui.igBeginDragDropSource(imgui.ImGuiDragDropFlags_None) == true) {
                    defer imgui.igEndDragDropSource();
                    _ = imgui.igSetDragDropPayload("EntityRef", entity, @sizeOf(Entity), 0);
                }
            }
        };
    } else if (T == SceneLayer) {
        return struct {
            const ParentComponent = SceneManager.ECSManagerScenes.ParentComponent;
            const ChildComponent = SceneManager.ECSManagerScenes.ChildComponent;
            const GetGroupFn = SceneManager.GetSceneGroup;

            pub fn ID(scene_layer: SceneLayer) u64 {
                return @intCast(scene_layer.mSceneID);
            }
            pub fn GetObject(scene_id: u64, scene_manager: *SceneManager) SceneLayer {
                return scene_manager.GetSceneLayer(@intCast(scene_id));
            }
            pub fn HandleDragDropSource(scene_layer: SceneLayer) void {
                if (imgui.igBeginDragDropSource(imgui.ImGuiDragDropFlags_None) == true) {
                    defer imgui.igEndDragDropSource();
                    _ = imgui.igSetDragDropPayload("SceneRef", scene_layer, @sizeOf(SceneLayer), 0);
                }
            }
        };
    } else if (T == Player) {
        return struct {
            const ParentComponent = SceneManager.ECSManagerPlayer.ParentComponent;
            const ChildComponent = SceneManager.ECSManagerPlayer.ChildComponent;
            const GetGroupFn = SceneManager.GetPlayerGroup;

            pub fn ID(entity: Player) u64 {
                return @intCast(entity.mEntityID);
            }
            pub fn GetObject(player_id: u64, scene_manager: *SceneManager) Player {
                return scene_manager.GetPlayer(@intCast(player_id));
            }
            pub fn HandleDragDropSource(player: Player) void {
                if (imgui.igBeginDragDropSource(imgui.ImGuiDragDropFlags_None) == true) {
                    defer imgui.igEndDragDropSource();
                    _ = imgui.igSetDragDropPayload("PlayerRef", player, @sizeOf(Player), 0);
                }
            }
        };
    } else if (T == GameMode) {
        return struct {
            const ParentComponent = SceneManager.ECSManagerGameMode.ParentComponent;
            const ChildComponent = SceneManager.ECSManagerGameMode.ChildComponent;
            const GetGroupFn = SceneManager.GetGameModeGroup;

            pub fn ID(entity: GameMode) u64 {
                return @intCast(entity.mEntityID);
            }
            pub fn GetObject(gamemode_id: u64, scene_manager: *SceneManager) GameMode {
                return scene_manager.GetGameMode(@intCast(gamemode_id));
            }
            pub fn HandleDragDropSource(game_mode: GameMode) void {
                if (imgui.igBeginDragDropSource(imgui.ImGuiDragDropFlags_None) == true) {
                    defer imgui.igEndDragDropSource();
                    _ = imgui.igSetDragDropPayload("GameModeRef", game_mode, @sizeOf(GameMode), 0);
                }
            }
        };
    } else {
        @compileError(@typeName(T) ++ " type not currently supported!");
    }
}

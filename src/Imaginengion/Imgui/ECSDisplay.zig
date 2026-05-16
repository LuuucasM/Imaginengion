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
const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;
const SelectedObject = @import("../Programs/EditorProgram.zig").SelectedObject;
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

pub fn OnImguiRender(self: ECSDisplayPanel, engine_context: *EngineContext, world_type: EngineContext.WorldType, comptime ecs_type: SceneManager.ECSType, selected_object: *?SelectedObject) !void {
    const zone = Tracy.ZoneInit("ECS Display OIR", @src());
    defer zone.Deinit();

    if (self._P_Open == false) return;

    const frame_allocator = engine_context.FrameAllocator();
    var already_popup = false;
    const available_region = imgui.igGetContentRegionAvail();

    const scene_manager = switch (world_type) {
        .Game => &engine_context.mGameWorld,
        .Simulate => &engine_context.mSimulateWorld,
        .Editor => &engine_context.mEditorWorld,
    };

    const window_name = try std.fmt.allocPrintSentinel(frame_allocator, "{s} - {s}", .{ @tagName(world_type), @tagName(ecs_type) }, 0);

    _ = imgui.igBegin(window_name.ptr, null, 0);
    defer imgui.igEnd();

    //child that is the width of the entire available region is needed so we can drag scenes from the content browser to load the scene
    if (imgui.igBeginChild_Str(@tagName(ecs_type), available_region, imgui.ImGuiChildFlags_None, imgui.ImGuiWindowFlags_NoMove | imgui.ImGuiWindowFlags_NoScrollbar)) {
        switch (ecs_type) {
            .GameObj => try RenderObjects(Entity, engine_context, scene_manager, &already_popup),
            .Scenes => try RenderObjects(SceneLayer, engine_context, scene_manager, &already_popup),
            .Players => try RenderObjects(Player, engine_context, scene_manager, &already_popup),
            .GameModes => try RenderObjects(GameMode, engine_context, scene_manager, &already_popup),
        }
    }
    imgui.igEndChild();

    if (imgui.igIsItemHovered(imgui.ImGuiHoveredFlags_None) and imgui.igIsMouseClicked_Bool(imgui.ImGuiMouseButton_Right, false)) {
        imgui.igOpenPopup_Str(@tagName(ecs_type), imgui.ImGuiPopupFlags_None);
    }
    if (imgui.igBeginPopup(@tagName(ecs_type), imgui.ImGuiWindowFlags_None)) {
        defer imgui.igEndPopup();
        already_popup = true;
        switch (ecs_type) {
            .GameObj => try HandleWindowMenu(Entity, engine_context, selected_object, scene_manager),
            .Scenes => try HandleWindowMenu(SceneLayer, engine_context, selected_object, scene_manager),
            .Players => try HandleWindowMenu(Player, engine_context, selected_object, scene_manager),
            .GameModes => try HandleWindowMenu(GameMode, engine_context, selected_object, scene_manager),
        }
    }
}

pub fn OnTogglePanelEvent(self: *ECSDisplayPanel) void {
    self._P_Open = !self._P_Open;
}

fn RenderObjects(comptime ObjectType: type, engine_context: *EngineContext, scene_manager: *SceneManager, already_popup: *bool) !void {
    const Traits = ObjectTraits(ObjectType);
    const frame_allocator = engine_context.FrameAllocator();

    const EntityTagQuery = GroupQuery{ .Component = EntityTagComponent };
    const ChildQuery = GroupQuery{ .Component = Traits.ChildComponent };

    const objects_list = try Traits.GetGroupFn(scene_manager, frame_allocator, .{ .Not = .{ .mFirst = &EntityTagQuery, .mSecond = &ChildQuery } });
    for (objects_list.items) |object_id| {
        const object = Traits.GetObject(object_id, scene_manager);
        try RenderObject(ObjectType, engine_context, object, already_popup);
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
        try Traits.SelectObject(engine_context, object);
    }

    if (!already_popup.* and imgui.igBeginPopupContextItem(object_name, imgui.ImGuiPopupFlags_MouseButtonRight)) {
        defer imgui.igEndPopup();
        already_popup.* = true;

        try Traits.HandleObjectContextMenu(engine_context, object);
    }

    Traits.HandleDragDropSource(object);

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
        try Traits.SelectObject(engine_context, object);
    }

    if (!already_popup.* and imgui.igBeginPopupContextItem(object_name, imgui.ImGuiPopupFlags_MouseButtonRight)) {
        defer imgui.igEndPopup();
        already_popup.* = true;

        try Traits.HandleObjectContextMenu(engine_context, object);
    }

    Traits.HandleDragDropSource(object);
}

fn RenderChildObjects(comptime ObjectType: type, engine_context: *EngineContext, parent_object: ObjectType, already_popup: *bool) anyerror!void {
    if (parent_object.GetIterator(.Child)) |iter_value| {
        var iter = iter_value;
        while (iter.next()) |child_object| {
            try RenderObject(ObjectType, engine_context, child_object, already_popup);
        }
    }
}

fn HandleWindowMenu(comptime ObjectType: type, engine_context: *EngineContext, selected_object: *?SelectedObject, scene_manager: *SceneManager) !void {
    const Traits = ObjectTraits(ObjectType);
    try Traits.HandleWindowContextMenu(engine_context, selected_object, scene_manager);
}

fn ObjectTraits(comptime T: type) type {
    if (T == Entity) {
        return struct {
            pub const ParentComponent = SceneManager.ECSManagerGameObj.ParentComponent;
            pub const ChildComponent = SceneManager.ECSManagerGameObj.ChildComponent;
            pub const GetGroupFn = SceneManager.GetEntityGroup;
            const Self = @This();
            pub fn ID(entity: Entity) u64 {
                return @intCast(entity.mEntityID);
            }
            pub fn GetObject(entity_id: u64, scene_manager: *SceneManager) Entity {
                return scene_manager.GetEntity(@intCast(entity_id));
            }
            pub fn HandleDragDropSource(entity: Entity) void {
                if (imgui.igBeginDragDropSource(imgui.ImGuiDragDropFlags_None) == true) {
                    defer imgui.igEndDragDropSource();
                    _ = imgui.igSetDragDropPayload("EntityRef", &entity, @sizeOf(Entity), 0);
                }
            }
            pub fn HandleObjectContextMenu(engine_context: *EngineContext, object: Entity) !void {
                if (imgui.igMenuItem_Bool("New Child Entity", "", false, true)) {
                    _ = try object.CreateChild(engine_context, .Entity, .{});
                }

                if (imgui.igMenuItem_Bool("Delete Entity", "", false, true)) {
                    try object.Delete(engine_context);
                }
            }
            pub fn HandleWindowContextMenu(engine_context: *EngineContext, selected_object: *?SelectedObject, _: *SceneManager) !void {
                var is_scene_layer = false;
                if (selected_object.*) |obj| {
                    if (std.meta.activeTag(obj) == .scene_layer) {
                        is_scene_layer = true;
                    }
                }
                if (imgui.igMenuItem_Bool("New Entity", "", false, is_scene_layer)) {
                    _ = try selected_object.*.?.scene_layer.CreateEntity(engine_context, .{});
                }
            }
            pub fn SelectObject(engine_context: *EngineContext, obj: Entity) !void {
                try engine_context.mImguiEventManager.Insert(engine_context.EngineAllocator(), .RenderEnd, .{
                    .SelectObjectEvent = .{
                        .mObject = .{ .entity = obj },
                    },
                });
            }
        };
    } else if (T == SceneLayer) {
        return struct {
            pub const ParentComponent = SceneManager.ECSManagerScenes.ParentComponent;
            pub const ChildComponent = SceneManager.ECSManagerScenes.ChildComponent;
            pub const GetGroupFn = SceneManager.GetSceneGroup;
            const Self = @This();
            pub fn ID(scene_layer: SceneLayer) u64 {
                return @intCast(scene_layer.mSceneID);
            }
            pub fn GetObject(scene_id: u64, scene_manager: *SceneManager) SceneLayer {
                return scene_manager.GetSceneLayer(@intCast(scene_id));
            }
            pub fn HandleDragDropSource(scene_layer: SceneLayer) void {
                if (imgui.igBeginDragDropSource(imgui.ImGuiDragDropFlags_None) == true) {
                    defer imgui.igEndDragDropSource();
                    _ = imgui.igSetDragDropPayload("SceneRef", &scene_layer, @sizeOf(SceneLayer), 0);
                }
            }
            pub fn HandleObjectContextMenu(engine_context: *EngineContext, object: SceneLayer) !void {
                if (imgui.igMenuItem_Bool("New Child Scene", "", false, true)) {
                    _ = try object.CreateChild(engine_context, .Entity, .{});
                }

                if (imgui.igMenuItem_Bool("New Entity", "", false, true)) {
                    _ = try object.CreateEntity(engine_context, .{});
                }

                if (imgui.igMenuItem_Bool("Delete Scene", "", false, true)) {
                    try object.Delete(engine_context);
                }
            }
            pub fn HandleWindowContextMenu(engine_context: *EngineContext, _: *?SelectedObject, scene_manager: *SceneManager) !void {
                if (imgui.igMenuItem_Bool("New Scene", "", false, true)) {
                    _ = try scene_manager.NewScene(engine_context, .GameLayer, .{});
                }
            }
            pub fn SelectObject(engine_context: *EngineContext, obj: SceneLayer) !void {
                try engine_context.mImguiEventManager.Insert(engine_context.EngineAllocator(), .RenderEnd, .{
                    .SelectObjectEvent = .{
                        .mObject = .{ .scene_layer = obj },
                    },
                });
            }
        };
    } else if (T == Player) {
        return struct {
            pub const ParentComponent = SceneManager.ECSManagerPlayer.ParentComponent;
            pub const ChildComponent = SceneManager.ECSManagerPlayer.ChildComponent;
            pub const GetGroupFn = SceneManager.GetPlayerGroup;
            const Self = @This();

            pub fn ID(entity: Player) u64 {
                return @intCast(entity.mEntityID);
            }
            pub fn GetObject(player_id: u64, scene_manager: *SceneManager) Player {
                return scene_manager.GetPlayer(@intCast(player_id));
            }
            pub fn HandleDragDropSource(player: Player) void {
                if (imgui.igBeginDragDropSource(imgui.ImGuiDragDropFlags_None) == true) {
                    defer imgui.igEndDragDropSource();
                    _ = imgui.igSetDragDropPayload("PlayerRef", &player, @sizeOf(Player), 0);
                }
            }
            pub fn HandleObjectContextMenu(engine_context: *EngineContext, object: Player) !void {
                if (imgui.igMenuItem_Bool("New Child Player", "", false, true)) {
                    _ = try object.CreateChild(engine_context, .Entity, .{});
                }

                if (imgui.igMenuItem_Bool("Delete Player", "", false, true)) {
                    try object.Delete(engine_context);
                }
            }
            pub fn HandleWindowContextMenu(engine_context: *EngineContext, _: *?SelectedObject, scene_manager: *SceneManager) !void {
                if (imgui.igMenuItem_Bool("New Player", "", false, true)) {
                    _ = try scene_manager.CreatePlayer(engine_context, .{});
                }
            }
            pub fn SelectObject(engine_context: *EngineContext, obj: Player) !void {
                try engine_context.mImguiEventManager.Insert(engine_context.EngineAllocator(), .RenderEnd, .{
                    .SelectObjectEvent = .{
                        .mObject = .{ .player = obj },
                    },
                });
            }
        };
    } else if (T == GameMode) {
        return struct {
            pub const ParentComponent = SceneManager.ECSManagerGameMode.ParentComponent;
            pub const ChildComponent = SceneManager.ECSManagerGameMode.ChildComponent;
            pub const GetGroupFn = SceneManager.GetGameModeGroup;
            const Self = @This();

            pub fn ID(entity: GameMode) u64 {
                return @intCast(entity.mEntityID);
            }
            pub fn GetObject(gamemode_id: u64, scene_manager: *SceneManager) GameMode {
                return scene_manager.GetGameMode(@intCast(gamemode_id));
            }
            pub fn HandleDragDropSource(game_mode: GameMode) void {
                if (imgui.igBeginDragDropSource(imgui.ImGuiDragDropFlags_None) == true) {
                    defer imgui.igEndDragDropSource();
                    _ = imgui.igSetDragDropPayload("GameModeRef", &game_mode, @sizeOf(GameMode), 0);
                }
            }
            pub fn HandleObjectContextMenu(engine_context: *EngineContext, object: GameMode) !void {
                if (imgui.igMenuItem_Bool("New Child Game Mode", "", false, true)) {
                    _ = try object.CreateChild(engine_context, .Entity, .{});
                }

                if (imgui.igMenuItem_Bool("Delete Game Mode", "", false, true)) {
                    try object.Delete(engine_context);
                }
            }
            pub fn HandleWindowContextMenu(engine_context: *EngineContext, _: *?SelectedObject, scene_manager: *SceneManager) !void {
                if (imgui.igMenuItem_Bool("New Game Mode", "", false, true)) {
                    _ = try scene_manager.CreateGameMode(engine_context, .{});
                }
            }
            pub fn SelectObject(engine_context: *EngineContext, obj: GameMode) !void {
                try engine_context.mImguiEventManager.Insert(engine_context.EngineAllocator(), .RenderEnd, .{
                    .SelectObjectEvent = .{
                        .mObject = .{ .gamemode = obj },
                    },
                });
            }
        };
    } else {
        @compileError(@typeName(T) ++ " type not currently supported!");
    }
}

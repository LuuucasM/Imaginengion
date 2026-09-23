const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const FileMetaData = @import("../ECSComponents/Asset/FileMetaData.zig");
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const WorldManager = @import("../Core/WorldManager.zig");
const EntityTagComponent = @import("../ECS/Components.zig").EntityTagComponent;
const Entity = @import("../ECSObjects/Entity.zig");
const Scene = @import("../ECSObjects/Scene.zig");
const Player = @import("../ECSObjects/Player.zig");
const GameContext = @import("../ECSObjects/GameContext.zig");
const GroupQuery = @import("../ECS/ECSManager.zig").GroupQuery;
const StackPosComponent = @import("../ECSComponents/Scene/StackPosComponent.zig");
const SelectedObject = @import("../Programs/EditorProgram.zig").SelectedObject;
const ImguiManager = @import("Imgui.zig");
const ECSDisplayPanel = @This();

/// Which of the world's ECS object types a given panel instance displays.
pub const ECSType = enum {
    GameObj,
    Scenes,
    Players,
    GameModes,
};

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

pub fn OnImguiRender(self: ECSDisplayPanel, engine_context: *EngineContext, world_type: EngineContext.WorldType, comptime ecs_type: ECSType, selected_object: *?SelectedObject) !void {
    const zone = Tracy.ZoneInit("ECS Display OIR", @src());
    defer zone.Deinit();

    if (self._P_Open == false) return;

    const frame_allocator = engine_context.FrameAllocator();
    const available_region = imgui.igGetContentRegionAvail();

    const world_manager = switch (world_type) {
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
            .GameObj => try RenderObjects(Entity, engine_context, world_manager),
            .Scenes => try RenderObjects(Scene, engine_context, world_manager),
            .Players => try RenderObjects(Player, engine_context, world_manager),
            .GameModes => try RenderObjects(GameContext, engine_context, world_manager),
        }

        //the panel's own context menu, submitted after the rows so imgui knows which row
        //(if any) the cursor is over. NoOpenOverItems means this only opens on a right
        //click that landed on empty space; a click on a row is claimed by that row's
        //BeginPopupContextItem instead. Both triggers fire on the same release, in the
        //same frame, so only one popup ever opens.
        if (imgui.igBeginPopupContextWindow(@tagName(ecs_type), imgui.ImGuiPopupFlags_MouseButtonRight | imgui.ImGuiPopupFlags_NoOpenOverItems)) {
            defer imgui.igEndPopup();
            switch (ecs_type) {
                .GameObj => try HandleWindowMenu(Entity, engine_context, selected_object, world_manager),
                .Scenes => try HandleWindowMenu(Scene, engine_context, selected_object, world_manager),
                .Players => try HandleWindowMenu(Player, engine_context, selected_object, world_manager),
                .GameModes => try HandleWindowMenu(GameContext, engine_context, selected_object, world_manager),
            }
        }
    }
    imgui.igEndChild();
}

pub fn OnTogglePanelEvent(self: *ECSDisplayPanel) void {
    self._P_Open = !self._P_Open;
}

fn RenderObjects(comptime ObjectType: type, engine_context: *EngineContext, world_manager: *WorldManager) !void {
    const Traits = ObjectTraits(ObjectType);
    const frame_allocator = engine_context.FrameAllocator();

    const objects_list = try Traits.GetGroupFn(world_manager, frame_allocator, Traits.RootQuery);

    //types that care about display order provide SortObjects; the rest render in
    //whatever order the ECS handed them back
    if (comptime @hasDecl(Traits, "SortObjects")) Traits.SortObjects(world_manager, objects_list.items);

    for (objects_list.items) |object_id| {
        const object = Traits.GetObject(object_id, world_manager);
        try RenderObject(ObjectType, engine_context, object);
    }
}

fn RenderObject(comptime ObjectType: type, engine_context: *EngineContext, object: ObjectType) !void {
    const Traits = ObjectTraits(ObjectType);
    if (object.HasComponent(Traits.ParentComponent)) {
        try RenderParentObject(ObjectType, engine_context, object);
    } else {
        try RenderLeafObject(ObjectType, engine_context, object);
    }
}

fn RenderParentObject(comptime ObjectType: type, engine_context: *EngineContext, object: ObjectType) !void {
    const Traits = ObjectTraits(ObjectType);
    const frame_allocator = engine_context.FrameAllocator();

    const object_name = try std.fmt.allocPrintSentinel(frame_allocator, "{s}###{d}", .{ object.GetName(), Traits.ID(object) }, 0);

    const is_entity_tree_open = imgui.igTreeNodeEx_Str(object_name, TREE_FLAGS);

    //select on release rather than press (IsItemClicked), matching the leaf Selectable. Selecting on
    //press swaps the components panel away before a drag from this node can be dropped into it.
    //Deactivated means the press started on this node, hovered means the release landed back on it,
    //so a drag that ends somewhere else never selects.
    if (imgui.igIsItemDeactivated() and imgui.igIsItemHovered(imgui.ImGuiHoveredFlags_None)) {
        try Traits.SelectObject(engine_context, object);
    }

    if (imgui.igBeginPopupContextItem(object_name, imgui.ImGuiPopupFlags_MouseButtonRight)) {
        defer imgui.igEndPopup();
        try Traits.HandleObjectContextMenu(engine_context, object);
    }

    Traits.HandleDragDropSource(object);

    if (is_entity_tree_open) {
        defer imgui.igTreePop();
        try RenderChildObjects(ObjectType, engine_context, object);
    }
}

fn RenderLeafObject(comptime ObjectType: type, engine_context: *EngineContext, object: ObjectType) !void {
    const Traits = ObjectTraits(ObjectType);
    const frame_allocator = engine_context.FrameAllocator();

    const object_name = try std.fmt.allocPrintSentinel(frame_allocator, "{s}###{d}", .{ object.GetName(), Traits.ID(object) }, 0);

    if (imgui.igSelectable_Bool(object_name, false, imgui.ImGuiSelectableFlags_None, .{ .x = 0, .y = 0 })) {
        try Traits.SelectObject(engine_context, object);
    }

    if (imgui.igBeginPopupContextItem(object_name, imgui.ImGuiPopupFlags_MouseButtonRight)) {
        defer imgui.igEndPopup();
        try Traits.HandleObjectContextMenu(engine_context, object);
    }

    Traits.HandleDragDropSource(object);
}

fn RenderChildObjects(comptime ObjectType: type, engine_context: *EngineContext, parent_object: ObjectType) anyerror!void {
    //an object with no children just yields nothing
    var iter = parent_object.GetIterator(.Child);
    while (iter.next()) |child_object| {
        try RenderObject(ObjectType, engine_context, child_object);
    }
}

fn HandleWindowMenu(comptime ObjectType: type, engine_context: *EngineContext, selected_object: *?SelectedObject, world_manager: *WorldManager) !void {
    const Traits = ObjectTraits(ObjectType);
    try Traits.HandleWindowContextMenu(engine_context, selected_object, world_manager);
}

fn ObjectTraits(comptime T: type) type {
    //Parent/Child come from the ECS instance that actually owns T, so the panel never
    //has to know which manager that is.
    const ECSManagerT = WorldManager.ManagerT(T).ECSManagerT;
    const EntityTagQuery = GroupQuery{ .Component = EntityTagComponent };
    const ChildQuery = GroupQuery{ .Component = ECSManagerT.ChildComponent };
    //top level objects: tagged as real objects, minus anything that is someone's child
    const RootQueryT = GroupQuery{ .Not = .{ .mFirst = &EntityTagQuery, .mSecond = &ChildQuery } };

    if (T == Entity) {
        return struct {
            pub const ParentComponent = ECSManagerT.ParentComponent;
            pub const ChildComponent = ECSManagerT.ChildComponent;
            pub const RootQuery = RootQueryT;
            pub const GetGroupFn = WorldManager.GetEntityGroup;
            const Self = @This();
            pub fn ID(entity: Entity) u64 {
                return @intCast(entity.mID);
            }
            pub fn GetObject(entity_id: u64, world_manager: *WorldManager) Entity {
                return world_manager.GetEntity(@intCast(entity_id));
            }
            pub fn HandleDragDropSource(entity: Entity) void {
                if (imgui.igBeginDragDropSource(imgui.ImGuiDragDropFlags_None) == true) {
                    defer imgui.igEndDragDropSource();
                    _ = imgui.igSetDragDropPayload(ImguiManager.ENTITY_REF_PAYLOAD, &entity, @sizeOf(Entity), 0);
                }
            }
            pub fn HandleObjectContextMenu(engine_context: *EngineContext, object: Entity) !void {
                if (imgui.igMenuItem_Bool("New Child Entity", "", false, true)) {
                    _ = try object.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
                }

                if (imgui.igMenuItem_Bool("Delete Entity", "", false, true)) {
                    try object.Delete(engine_context);
                    try engine_context.mGameEventManager.Insert(
                        engine_context.EngineAllocator(),
                        .EndOfFrame,
                        .{ .DestroyEntityEvent = .{ .mEntity = object } },
                    );
                }
            }
            pub fn HandleWindowContextMenu(engine_context: *EngineContext, selected_object: *?SelectedObject, _: *WorldManager) !void {
                var is_scene_layer = false;
                if (selected_object.*) |obj| {
                    if (std.meta.activeTag(obj) == .scene_layer) {
                        is_scene_layer = true;
                    }
                }
                if (imgui.igMenuItem_Bool("New Entity", "", false, is_scene_layer)) {
                    _ = try selected_object.*.?.scene_layer.CreateEntity(engine_context, Entity.DefaultConfig);
                }
            }
            pub fn SelectObject(engine_context: *EngineContext, obj: Entity) !void {
                try engine_context.mImguiEventManager.Insert(engine_context.EngineAllocator(), .EndOfFrame, .{
                    .SelectObjectEvent = .{
                        .mObject = .{ .entity = obj },
                    },
                });
            }
        };
    } else if (T == Scene) {
        return struct {
            pub const ParentComponent = ECSManagerT.ParentComponent;
            pub const ChildComponent = ECSManagerT.ChildComponent;
            pub const RootQuery = RootQueryT;
            pub const GetGroupFn = WorldManager.GetSceneGroup;
            const Self = @This();
            pub fn ID(scene_layer: Scene) u64 {
                return @intCast(scene_layer.mID);
            }
            pub fn GetObject(scene_id: u64, world_manager: *WorldManager) Scene {
                return world_manager.GetScene(@intCast(scene_id));
            }

            /// Scenes render top to bottom by stack position, highest first, so the
            /// topmost layer is the topmost row.
            pub fn SortObjects(world_manager: *WorldManager, objects: []Scene.Type) void {
                std.sort.insertion(Scene.Type, objects, world_manager, Self.SortByStackPos);
            }

            fn SortByStackPos(world_manager: *WorldManager, a: Scene.Type, b: Scene.Type) bool {
                return Self.StackPosOf(world_manager, b) < Self.StackPosOf(world_manager, a);
            }

            /// A scene only gets a stack position by going through CreateScene, so a
            /// scene that arrived another way sorts to the bottom rather than crashing.
            fn StackPosOf(world_manager: *WorldManager, scene_id: Scene.Type) usize {
                const stack_pos = world_manager.mSManager.GetComponent(StackPosComponent, scene_id) orelse return 0;
                return stack_pos.mPosition;
            }
            pub fn HandleDragDropSource(scene_layer: Scene) void {
                if (imgui.igBeginDragDropSource(imgui.ImGuiDragDropFlags_None) == true) {
                    defer imgui.igEndDragDropSource();
                    _ = imgui.igSetDragDropPayload("SceneRef", &scene_layer, @sizeOf(Scene), 0);
                }
            }
            pub fn HandleObjectContextMenu(engine_context: *EngineContext, object: Scene) !void {
                if (imgui.igMenuItem_Bool("New Child Scene", "", false, true)) {
                    _ = try object.CreateChild(engine_context, .Entity, Scene.DefaultConfig);
                }

                if (imgui.igMenuItem_Bool("New Entity", "", false, true)) {
                    _ = try object.CreateEntity(engine_context, Entity.DefaultConfig);
                }

                if (imgui.igMenuItem_Bool("Delete Scene", "", false, true)) {
                    try object.Delete(engine_context);
                    try engine_context.mGameEventManager.Insert(
                        engine_context.EngineAllocator(),
                        .EndOfFrame,
                        .{ .DestroySceneEvent = .{ .mScene = object } },
                    );
                }
            }
            pub fn HandleWindowContextMenu(engine_context: *EngineContext, _: *?SelectedObject, world_manager: *WorldManager) !void {
                if (imgui.igMenuItem_Bool("New Scene", "", false, true)) {
                    _ = try world_manager.NewScene(engine_context, .GameLayer, Scene.DefaultConfig);
                }
            }
            pub fn SelectObject(engine_context: *EngineContext, obj: Scene) !void {
                try engine_context.mImguiEventManager.Insert(engine_context.EngineAllocator(), .EndOfFrame, .{
                    .SelectObjectEvent = .{
                        .mObject = .{ .scene_layer = obj },
                    },
                });
            }
        };
    } else if (T == Player) {
        return struct {
            pub const ParentComponent = ECSManagerT.ParentComponent;
            pub const ChildComponent = ECSManagerT.ChildComponent;
            pub const RootQuery = RootQueryT;
            pub const GetGroupFn = WorldManager.GetPlayerGroup;
            const Self = @This();

            pub fn ID(entity: Player) u64 {
                return @intCast(entity.mID);
            }
            pub fn GetObject(player_id: u64, world_manager: *WorldManager) Player {
                return world_manager.GetPlayer(@intCast(player_id));
            }
            pub fn HandleDragDropSource(player: Player) void {
                if (imgui.igBeginDragDropSource(imgui.ImGuiDragDropFlags_None) == true) {
                    defer imgui.igEndDragDropSource();
                    _ = imgui.igSetDragDropPayload("PlayerRef", &player, @sizeOf(Player), 0);
                }
            }
            pub fn HandleObjectContextMenu(engine_context: *EngineContext, object: Player) !void {
                if (imgui.igMenuItem_Bool("New Child Player", "", false, true)) {
                    _ = try object.CreateChild(engine_context, .Entity, Player.DefaultConfig);
                }

                if (imgui.igMenuItem_Bool("Delete Player", "", false, true)) {
                    try object.Delete(engine_context);
                    try engine_context.mGameEventManager.Insert(
                        engine_context.EngineAllocator(),
                        .EndOfFrame,
                        .{ .DestroyPlayerEvent = .{ .mPlayer = object } },
                    );
                }
            }
            pub fn HandleWindowContextMenu(engine_context: *EngineContext, _: *?SelectedObject, world_manager: *WorldManager) !void {
                if (imgui.igMenuItem_Bool("New Player", "", false, true)) {
                    _ = try world_manager.CreatePlayer(engine_context, Player.DefaultConfig);
                }
            }
            pub fn SelectObject(engine_context: *EngineContext, obj: Player) !void {
                try engine_context.mImguiEventManager.Insert(engine_context.EngineAllocator(), .EndOfFrame, .{
                    .SelectObjectEvent = .{
                        .mObject = .{ .player = obj },
                    },
                });
            }
        };
    } else if (T == GameContext) {
        return struct {
            pub const ParentComponent = ECSManagerT.ParentComponent;
            pub const ChildComponent = ECSManagerT.ChildComponent;
            pub const RootQuery = RootQueryT;
            pub const GetGroupFn = WorldManager.GetGameContextGroup;
            const Self = @This();

            pub fn ID(entity: GameContext) u64 {
                return @intCast(entity.mID);
            }
            pub fn GetObject(gamecontext_id: u64, world_manager: *WorldManager) GameContext {
                return world_manager.GetGameContext(@intCast(gamecontext_id));
            }
            pub fn HandleDragDropSource(game_context: GameContext) void {
                if (imgui.igBeginDragDropSource(imgui.ImGuiDragDropFlags_None) == true) {
                    defer imgui.igEndDragDropSource();
                    _ = imgui.igSetDragDropPayload("GameContextRef", &game_context, @sizeOf(GameContext), 0);
                }
            }
            pub fn HandleObjectContextMenu(engine_context: *EngineContext, object: GameContext) !void {
                if (imgui.igMenuItem_Bool("New Child Game Context", "", false, true)) {
                    _ = try object.CreateChild(engine_context, .Entity, GameContext.DefaultConfig);
                }

                if (imgui.igMenuItem_Bool("Delete Game Context", "", false, true)) {
                    try object.Delete(engine_context);
                    try engine_context.mGameEventManager.Insert(
                        engine_context.EngineAllocator(),
                        .EndOfFrame,
                        .{ .DestroyGameContextEvent = .{ .mGameContext = object } },
                    );
                }
            }
            pub fn HandleWindowContextMenu(engine_context: *EngineContext, _: *?SelectedObject, world_manager: *WorldManager) !void {
                if (imgui.igMenuItem_Bool("New Game Mode", "", false, true)) {
                    _ = try world_manager.CreateGameContext(engine_context, GameContext.DefaultConfig);
                }
            }
            pub fn SelectObject(engine_context: *EngineContext, obj: GameContext) !void {
                try engine_context.mImguiEventManager.Insert(engine_context.EngineAllocator(), .EndOfFrame, .{
                    .SelectObjectEvent = .{
                        .mObject = .{ .gamecontext = obj },
                    },
                });
            }
        };
    } else {
        @compileError(@typeName(T) ++ " type not currently supported!");
    }
}

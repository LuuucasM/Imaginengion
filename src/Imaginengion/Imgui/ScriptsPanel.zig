const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const Entity = @import("../GameObjects/Entity.zig");
const EntityScriptComponent = @import("../GameObjects/Components.zig").ScriptComponent;
const EngineContext = @import("../Core/EngineContext.zig");
const Assets = @import("../Assets/Assets.zig");
const FileMetaData = Assets.FileMetaData;
const ScriptAsset = Assets.ScriptAsset;
const Components = @import("../GameObjects/Components.zig");
const EntityParentComponent = @import("../ECS/Components.zig").ParentComponent(Entity.Type);
const EntityChildComponent = @import("../ECS/Components.zig").ChildComponent(Entity.Type);
const SelectedObject = @import("../Programs/EditorProgram.zig").SelectedObject;

const SceneLayer = @import("../Scene/SceneLayer.zig");
const Player = @import("../Players/Player.zig");
const GameMode = @import("../GameModes/GameMode.zig");

const Tracy = @import("../Core/Tracy.zig");

const ScriptsPanel = @This();

_P_Open: bool = true,

pub fn OnImguiRender(self: *ScriptsPanel, engine_context: *EngineContext, selected_object_opt: ?SelectedObject) !void {
    const zone = Tracy.ZoneInit("Scripts Panel OIR", @src());
    defer zone.Deinit();

    if (self._P_Open == false) return;

    if (selected_object_opt) |selected_object| {
        switch (selected_object) {
            .entity => |e| try RenderBegin(Entity, engine_context, e),
            .scene_layer => |s| try RenderBegin(SceneLayer, engine_context, s),
            .player => |p| try RenderBegin(Player, engine_context, p),
            .gamemode => |g| try RenderBegin(GameMode, engine_context, g),
        }
        defer imgui.igEnd();

        const available_region = imgui.igGetContentRegionAvail();

        //making a child so that drag drop target will tae the entire available region
        if (imgui.igBeginChild_Str("SceneChild", available_region, imgui.ImGuiChildFlags_None, imgui.ImGuiWindowFlags_NoMove | imgui.ImGuiWindowFlags_NoScrollbar)) {
            switch (selected_object) {
                .entity => |e| try RenderScript(Entity, engine_context, e),
                .scene_layer => |s| try RenderScript(SceneLayer, engine_context, s),
                .player => |p| try RenderScript(Player, engine_context, p),
                .gamemode => |g| try RenderScript(GameMode, engine_context, g),
            }
        }
        imgui.igEndChild();

        switch (selected_object) {
            .entity => |e| try ObjectTraits(Entity).HandleDragDropTarget(engine_context, e),
            .scene_layer => |s| try ObjectTraits(SceneLayer).HandleDragDropTarget(engine_context, s),
            .player => |p| try ObjectTraits(Player).HandleDragDropTarget(engine_context, p),
            .gamemode => |g| try ObjectTraits(GameMode).HandleDragDropTarget(engine_context, g),
        }
    } else {
        _ = imgui.igBegin("Scripts - No Entity###Scripts\x00", null, 0);
        defer imgui.igEnd();
    }
}

pub fn OnTogglePanelEvent(self: *ScriptsPanel) void {
    self._P_Open = !self._P_Open;
}

fn RenderBegin(comptime ObjectType: type, engine_context: *EngineContext, object: ObjectType) !void {
    const object_name = object.GetName();
    const name_len = std.mem.indexOf(u8, object_name, &.{0}) orelse object_name.len;
    const trimmed_name = object_name[0..name_len];
    const name = try std.fmt.allocPrintSentinel(engine_context.FrameAllocator(), "Components - {s}###Components\x00", .{trimmed_name}, 0);

    _ = imgui.igBegin(name.ptr, null, 0);
}

fn RenderScript(comptime ObjectType: type, engine_context: *EngineContext, object: ObjectType) !void {
    if (object.GetIterator(.Script)) |iter_obj| {
        var iter = iter_obj;
        while (iter.next()) |script_entity| {
            const script_name = script_entity.GetName();

            if (imgui.igSelectable_Bool(script_name.ptr, false, imgui.ImGuiSelectableFlags_None, .{ .x = 0.0, .y = 0.0 })) {}

            if (imgui.igBeginPopupContextItem(script_name.ptr, imgui.ImGuiPopupFlags_MouseButtonRight)) {
                defer imgui.igEndPopup();

                if (imgui.igMenuItem_Bool("Delete Script", "", false, true)) {
                    try script_entity.Delete(engine_context);
                }
            }
        }
    }
}

fn ObjectTraits(comptime T: type) type {
    if (T == Entity) {
        const EntityComponents = @import("../GameObjects/Components.zig");

        return struct {
            const ComponentsPanelList = EntityComponents.ComponentPanelList;
            pub fn HandleDragDropTarget(engine_context: *EngineContext, entity: Entity) !void {
                //drag drop target for scripts
                if (imgui.igBeginDragDropTarget() == true) {
                    defer imgui.igEndDragDropTarget();
                    if (imgui.igAcceptDragDropPayload("EntityScript", imgui.ImGuiDragDropFlags_None)) |payload| {
                        const path_len = payload.*.DataSize;
                        const rel_path = @as([*]const u8, @ptrCast(@alignCast(payload.*.Data)))[0..@intCast(path_len)];
                        try entity.AddComponentScript(engine_context, rel_path, .Prj);
                    }
                }
            }
        };
    } else if (T == SceneLayer) {
        const SceneComponents = @import("../Scene/SceneComponents.zig");
        return struct {
            const ComponentsPanelList = SceneComponents.ComponentsPanelList;
            pub fn HandleDragDropTarget(engine_context: *EngineContext, scene_layer: SceneLayer) !void {
                //drag drop target for scripts
                if (imgui.igBeginDragDropTarget() == true) {
                    defer imgui.igEndDragDropTarget();
                    if (imgui.igAcceptDragDropPayload("SceneScript", imgui.ImGuiDragDropFlags_None)) |payload| {
                        const path_len = payload.*.DataSize;
                        const rel_path = @as([*]const u8, @ptrCast(@alignCast(payload.*.Data)))[0..@intCast(path_len)];
                        try scene_layer.AddComponentScript(engine_context, rel_path, .Prj);
                    }
                }
            }
        };
    } else if (T == Player) {
        const PlayerComponents = @import("../Players/Components.zig");
        return struct {
            const ComponentsPanelList = PlayerComponents.ComponentsPanelList;
            pub fn HandleDragDropTarget(engine_context: *EngineContext, player: Player) !void {
                //drag drop target for scripts
                if (imgui.igBeginDragDropTarget() == true) {
                    defer imgui.igEndDragDropTarget();
                    if (imgui.igAcceptDragDropPayload("PlayerScript", imgui.ImGuiDragDropFlags_None)) |payload| {
                        const path_len = payload.*.DataSize;
                        const rel_path = @as([*]const u8, @ptrCast(@alignCast(payload.*.Data)))[0..@intCast(path_len)];
                        try player.AddComponentScript(engine_context, rel_path, .Prj);
                    }
                }
            }
        };
    } else if (T == GameMode) {
        const GameModeComponents = @import("../GameModes/Components.zig");
        return struct {
            const ComponentsPanelList = GameModeComponents.ComponentsPanelList;
            pub fn HandleDragDropTarget(engine_context: *EngineContext, game_mode: GameMode) !void {
                //drag drop target for scripts
                if (imgui.igBeginDragDropTarget() == true) {
                    defer imgui.igEndDragDropTarget();
                    if (imgui.igAcceptDragDropPayload("GameModeScript", imgui.ImGuiDragDropFlags_None)) |payload| {
                        const path_len = payload.*.DataSize;
                        const rel_path = @as([*]const u8, @ptrCast(@alignCast(payload.*.Data)))[0..@intCast(path_len)];
                        try game_mode.AddComponentScript(engine_context, rel_path, .Prj);
                    }
                }
            }
        };
    } else {
        @compileError(@typeName(T) ++ "This type is not supported currently");
    }
}

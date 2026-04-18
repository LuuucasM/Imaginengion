const std = @import("std");
const imgui = @import("../Core/CImports.zig").imgui;
const Entity = @import("../GameObjects/Entity.zig");
const SceneLayer = @import("../Scene/SceneLayer.zig");
const Player = @import("../Players/Player.zig");
const GameMode = @import("../GameModes/GameMode.zig");

const Renderer = @import("../Renderer/Renderer.zig");

const ComponentsPanel = @This();

const EngineContext = @import("../Core/EngineContext.zig");

const AssetHandle = @import("../Assets/AssetHandle.zig");
const Assets = @import("../Assets/Assets.zig");
const SelectedObject = @import("../Programs/EditorProgram.zig").SelectedObject;

const Tracy = @import("../Core/Tracy.zig");

_P_Open: bool = true,

pub fn Init(_: *ComponentsPanel) void {}

pub fn OnImguiRender(self: ComponentsPanel, engine_context: *EngineContext, selected_object_opt: ?SelectedObject) !void {
    const zone = Tracy.ZoneInit("Components Panel OIR", @src());
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

        switch (selected_object) {
            .entity => |e| try RenderComponents(Entity, engine_context, e),
            .scene_layer => |s| try RenderComponents(SceneLayer, engine_context, s),
            .player => |p| try RenderComponents(Player, engine_context, p),
            .gamemode => |g| try RenderComponents(GameMode, engine_context, g),
        }
    } else {
        _ = imgui.igBegin("Components - No Entity###Components\x00", null, 0);
        defer imgui.igEnd();
    }
}

fn RenderBegin(comptime ObjectType: type, engine_context: *EngineContext, object: ObjectType) !void {
    const object_name = object.GetName();
    const name_len = std.mem.indexOf(u8, object_name, &.{0}) orelse object_name.len;
    const trimmed_name = object_name[0..name_len];
    const name = try std.fmt.allocPrintSentinel(engine_context.FrameAllocator(), "Components - {s}###Components\x00", .{trimmed_name}, 0);

    _ = imgui.igBegin(name.ptr, null, 0);
}

fn RenderComponents(comptime ObjectType: type, engine_context: *EngineContext, object: ObjectType) !void {
    if (imgui.igIsWindowHovered(imgui.ImGuiHoveredFlags_None) == true and imgui.igIsMouseClicked_Bool(imgui.ImGuiMouseButton_Right, false) == true) {
        imgui.igOpenPopup_Str("RightClickPopup", imgui.ImGuiPopupFlags_None);
    }
    if (imgui.igBeginPopup("RightClickPopup", imgui.ImGuiWindowFlags_None) == true) {
        defer imgui.igEndPopup();
        try NewObjectComponentPopup(ObjectType, engine_context, object);
    }

    try ObjectImguiRender(ObjectType, engine_context, object);
}

pub fn OnTogglePanelEvent(self: *ComponentsPanel) void {
    self._P_Open = !self._P_Open;
}

fn ObjectImguiRender(comptime ObjectType: type, engine_context: *EngineContext, object: ObjectType) !void {
    const traits = ObjectTraits(ObjectType);
    inline for (traits.ComponentsPanelList) |component_type| {
        if (object.HasComponent(component_type)) {
            try PrintObjectComponent(component_type, engine_context, object);
        }
    }
}

fn PrintObjectComponent(comptime component_type: type, engine_context: *EngineContext, object: anytype) !void {
    const tree_flags = imgui.ImGuiTreeNodeFlags_OpenOnArrow;
    const is_tree_open = imgui.igTreeNodeEx_Str(@typeName(component_type), tree_flags);
    if (imgui.igBeginPopupContextItem(@typeName(component_type), imgui.ImGuiPopupFlags_MouseButtonRight)) {
        defer imgui.igEndPopup();

        if (imgui.igMenuItem_Bool("Delete Component", "", false, true)) {
            try object.RemoveComponent(engine_context.EngineAllocator(), component_type);
        }
    }
    if (is_tree_open) {
        defer imgui.igTreePop();
        if (@hasDecl(component_type, "EditorRender")) {
            const component_ptr = object.GetComponent(component_type).?;
            try component_ptr.EditorRender(engine_context);
        }
    }
}

fn NewObjectComponentPopup(comptime ObjectType: type, engine_context: *EngineContext, object: ObjectType) !void {
    const traits = ObjectTraits(ObjectType);
    inline for (traits.ComponentsPanelList) |component_type| {
        if (!object.HasComponent(component_type)) {
            if (imgui.igMenuItem_Bool(component_type.Name.ptr, "", false, true)) {
                defer imgui.igCloseCurrentPopup();
                _ = try object.AddComponent(engine_context, component_type{});
            }
        }
    }
}

fn ObjectTraits(comptime T: type) type {
    if (T == Entity) {
        const EntityComponents = @import("../GameObjects/Components.zig");

        return struct {
            const ComponentsPanelList = EntityComponents.ComponentPanelList;
        };
    } else if (T == SceneLayer) {
        const SceneComponents = @import("../Scene/SceneComponents.zig");
        return struct {
            const ComponentsPanelList = SceneComponents.ComponentsPanelList;
        };
    } else if (T == Player) {
        const PlayerComponents = @import("../Players/Components.zig");
        return struct {
            const ComponentsPanelList = PlayerComponents.ComponentsPanelList;
        };
    } else if (T == GameMode) {
        const GameModeComponents = @import("../GameModes/Components.zig");
        return struct {
            const ComponentsPanelList = GameModeComponents.ComponentsPanelList;
        };
    } else {
        @compileError(@typeName(T) ++ "This type is not supported currently");
    }
}

const std = @import("std");
const imgui = @import("../Core/CImports.zig").imgui;
const ImguiEventManager = @import("../Events/ImguiEventManager.zig");
const EditorWindow = @import("EditorWindow.zig");
const ImguiEvent = @import("../Events/ImguiEvent.zig").ImguiEvent;
const Entity = @import("../GameObjects/Entity.zig");
const SceneLayer = @import("../Scene/SceneLayer.zig");
const ComponentsPanel = @This();

const EntityComponents = @import("../GameObjects/Components.zig");
const EntityIDComponent = EntityComponents.IDComponent;
const CameraComponent = EntityComponents.CameraComponent;
const CircleRenderComponent = EntityComponents.CircleRenderComponent;
const ControllerComponent = EntityComponents.ControllerComponent;
const EntityNameComponent = EntityComponents.NameComponent;
const QuadComponent = EntityComponents.QuadComponent;
const SpriteRenderComponent = EntityComponents.SpriteRenderComponent;
const TransformComponent = EntityComponents.TransformComponent;

const AssetManager = @import("../Assets/AssetManager.zig");
const AssetHandle = @import("../Assets/AssetHandle.zig");

_P_Open: bool,
mSelectedScene: ?SceneLayer,
mSelectedEntity: ?Entity,

pub fn Init() ComponentsPanel {
    return ComponentsPanel{
        ._P_Open = true,
        .mSelectedEntity = null,
        .mSelectedScene = null,
    };
}

pub fn OnImguiRender(self: ComponentsPanel) !void {
    if (self._P_Open == false) return;

    if (self.mSelectedEntity) |entity| {
        var buffer: [300]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);
        const entity_name = entity.GetName();
        const name_len = std.mem.indexOf(u8, entity_name, &.{0}) orelse entity_name.len;
        const trimmed_name = entity_name[0..name_len];
        const name = try std.fmt.allocPrintZ(fba.allocator(), "Components - {s}###Components\x00", .{trimmed_name});

        _ = imgui.igBegin(name.ptr, null, 0);
    } else {
        _ = imgui.igBegin("Components - No Entity###Components\x00", null, 0);
    }
    defer imgui.igEnd();

    if (self.mSelectedEntity) |entity| {
        var region_size: imgui.ImVec2 = .{ .x = 0, .y = 0 };
        imgui.igGetContentRegionAvail(&region_size);
        if (imgui.igButton("Add Component", .{ .x = region_size.x, .y = 20 }) == true) {
            imgui.igOpenPopup_Str("AddComponent", imgui.ImGuiPopupFlags_None);
        }
        if (imgui.igBeginPopup("AddComponent", imgui.ImGuiWindowFlags_None) == true) {
            defer imgui.igEndPopup();
            try AddComponentPopupMenu(entity);
        }
        try EntityImguiRender(entity);
    }
}

pub fn OnImguiEvent(self: *ComponentsPanel, event: *ImguiEvent) void {
    switch (event.*) {
        .ET_TogglePanelEvent => self.OnTogglePanelEvent(),
        else => @panic("Response to that event has not bee implemented yet in ComponentsPanel!\n"),
    }
}

pub fn OnTogglePanelEvent(self: *ComponentsPanel) void {
    self._P_Open = !self._P_Open;
}

pub fn OnSelectEntityEvent(self: *ComponentsPanel, new_selected_entity: ?Entity) void {
    self.mSelectedEntity = new_selected_entity;
}

pub fn OnSelectSceneEvent(self: *ComponentsPanel, new_selected_scene: ?SceneLayer) void {
    self.mSelectedScene = new_selected_scene;
}

fn EntityImguiRender(entity: Entity) !void {
    if (entity.HasComponent(EntityIDComponent)) {
        if (imgui.igSelectable_Bool(@typeName(EntityIDComponent), false, imgui.ImGuiSelectableFlags_None, .{ .x = 0, .y = 0 }) == true) {
            const new_event = ImguiEvent{
                .ET_SelectComponentEvent = .{
                    .mEditorWindow = EditorWindow.Init(entity.GetComponent(EntityIDComponent), entity),
                },
            };
            try ImguiEventManager.Insert(new_event);
        }
    }
    if (entity.HasComponent(EntityNameComponent) == true) {
        if (imgui.igSelectable_Bool(@typeName(EntityNameComponent), false, imgui.ImGuiSelectableFlags_None, .{ .x = 0, .y = 0 }) == true) {
            const new_event = ImguiEvent{
                .ET_SelectComponentEvent = .{
                    .mEditorWindow = EditorWindow.Init(entity.GetComponent(EntityNameComponent), entity),
                },
            };
            try ImguiEventManager.Insert(new_event);
        }
    }
    if (entity.HasComponent(TransformComponent) == true) {
        if (imgui.igSelectable_Bool(@typeName(TransformComponent), false, imgui.ImGuiSelectableFlags_None, .{ .x = 0, .y = 0 }) == true) {
            const new_editor_window = EditorWindow.Init(entity.GetComponent(TransformComponent), entity);
            const new_event = ImguiEvent{
                .ET_SelectComponentEvent = .{
                    .mEditorWindow = new_editor_window,
                },
            };
            try ImguiEventManager.Insert(new_event);
        }
    }
    if (entity.HasComponent(CameraComponent) == true) {
        if (imgui.igSelectable_Bool(@typeName(CameraComponent), false, imgui.ImGuiSelectableFlags_None, .{ .x = 0, .y = 0 }) == true) {
            const new_event = ImguiEvent{
                .ET_SelectComponentEvent = .{
                    .mEditorWindow = EditorWindow.Init(entity.GetComponent(CameraComponent), entity),
                },
            };
            try ImguiEventManager.Insert(new_event);
        }
    }
    if (entity.HasComponent(CircleRenderComponent) == true) {
        if (imgui.igSelectable_Bool(@typeName(CircleRenderComponent), false, imgui.ImGuiSelectableFlags_None, .{ .x = 0, .y = 0 }) == true) {
            const new_event = ImguiEvent{
                .ET_SelectComponentEvent = .{
                    .mEditorWindow = EditorWindow.Init(entity.GetComponent(CircleRenderComponent), entity),
                },
            };
            try ImguiEventManager.Insert(new_event);
        }
    }
    if (entity.HasComponent(QuadComponent) == true) {
        if (imgui.igSelectable_Bool(@typeName(QuadComponent), false, imgui.ImGuiSelectableFlags_None, .{ .x = 0, .y = 0 }) == true) {
            const new_event = ImguiEvent{
                .ET_SelectComponentEvent = .{
                    .mEditorWindow = EditorWindow.Init(entity.GetComponent(QuadComponent), entity),
                },
            };
            try ImguiEventManager.Insert(new_event);
        }
    }
    if (entity.HasComponent(SpriteRenderComponent) == true) {
        if (imgui.igSelectable_Bool(@typeName(SpriteRenderComponent), false, imgui.ImGuiSelectableFlags_None, .{ .x = 0, .y = 0 }) == true) {
            const new_event = ImguiEvent{
                .ET_SelectComponentEvent = .{
                    .mEditorWindow = EditorWindow.Init(entity.GetComponent(SpriteRenderComponent), entity),
                },
            };
            try ImguiEventManager.Insert(new_event);
        }
    }
}

fn AddComponentPopupMenu(entity: Entity) !void {
    if (entity.HasComponent(CameraComponent) == false) {
        if (imgui.igMenuItem_Bool("CameraComponent", "", false, true) == true) {
            _ = try entity.AddComponent(CameraComponent, null);
            imgui.igCloseCurrentPopup();
        }
    }
    if (entity.HasComponent(CircleRenderComponent) == false and entity.HasComponent(SpriteRenderComponent) == false) {
        if (imgui.igMenuItem_Bool("CircleRenderComponent", "", false, true) == true) {
            _ = try entity.AddComponent(CircleRenderComponent, null);
            imgui.igCloseCurrentPopup();
        }
    }
    if (entity.HasComponent(ControllerComponent) == false) {
        if (imgui.igMenuItem_Bool("ControllerComponent", "", false, true) == true) {
            _ = try entity.AddComponent(ControllerComponent, null);
            imgui.igCloseCurrentPopup();
        }
    }
    if (entity.HasComponent(QuadComponent) == false and entity.HasComponent(CircleRenderComponent) == false and entity.HasComponent(SpriteRenderComponent) == false) {
        if (imgui.igMenuItem_Bool("QuadComponent", "", false, true) == true) {
            const new_sprite_component = try entity.AddComponent(QuadComponent, null);
            new_sprite_component.mTexture = try AssetManager.GetAssetHandleRef("assets/textures/whitetexture.png", .Eng);
            imgui.igCloseCurrentPopup();
        }
    }
    if (entity.HasComponent(SpriteRenderComponent) == false and entity.HasComponent(CircleRenderComponent) == false) {
        if (imgui.igMenuItem_Bool("SpriteRenderComponent", "", false, true) == true) {
            const new_sprite_component = try entity.AddComponent(SpriteRenderComponent, null);
            new_sprite_component.mTexture = try AssetManager.GetAssetHandleRef("assets/textures/whitetexture.png", .Eng);
            imgui.igCloseCurrentPopup();
        }
    }
}

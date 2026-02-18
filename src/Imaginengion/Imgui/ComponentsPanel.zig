const std = @import("std");
const imgui = @import("../Core/CImports.zig").imgui;
const ImguiEvent = @import("../Events/ImguiEvent.zig").ImguiEvent;
const Entity = @import("../GameObjects/Entity.zig");
const SceneLayer = @import("../Scene/SceneLayer.zig");

const Renderer = @import("../Renderer/Renderer.zig");

const FrameBuffer = @import("../FrameBuffers/FrameBuffer.zig");
const VertexArray = @import("../VertexArrays/VertexArray.zig");
const VertexBuffer = @import("../VertexBuffers/VertexBuffer.zig");
const IndexBuffer = @import("../IndexBuffers/IndexBuffer.zig");
const TextureFormat = FrameBuffer.TextureFormat;

const ComponentsPanel = @This();

const EntityComponents = @import("../GameObjects/Components.zig");
const QuadComponent = EntityComponents.QuadComponent;
const TextComponent = EntityComponents.TextComponent;
const AudioComponent = EntityComponents.AudioComponent;

const EngineContext = @import("../Core/EngineContext.zig");

const AssetHandle = @import("../Assets/AssetHandle.zig");
const Assets = @import("../Assets/Assets.zig");

const ImguiUtils = @import("ImguiUtils.zig");

const Tracy = @import("../Core/Tracy.zig");

_P_Open: bool = true,
mSelectedScene: ?SceneLayer = null,
mSelectedEntity: ?Entity = null,

pub fn Init(_: *ComponentsPanel) void {}

pub fn OnImguiRender(self: ComponentsPanel, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("Components Panel OIR", @src());
    defer zone.Deinit();

    if (self._P_Open == false) return;

    if (self.mSelectedEntity) |entity| {
        const entity_name = entity.GetName();
        const name_len = std.mem.indexOf(u8, entity_name, &.{0}) orelse entity_name.len;
        const trimmed_name = entity_name[0..name_len];
        const name = try std.fmt.allocPrintSentinel(engine_context.FrameAllocator(), "Components - {s}###Components\x00", .{trimmed_name}, 0);

        _ = imgui.igBegin(name.ptr, null, 0);
    } else {
        _ = imgui.igBegin("Components - No Entity###Components\x00", null, 0);
    }
    defer imgui.igEnd();

    if (self.mSelectedEntity) |entity| {
        if (imgui.igIsWindowHovered(imgui.ImGuiHoveredFlags_None) == true and imgui.igIsMouseClicked_Bool(imgui.ImGuiMouseButton_Right, false) == true) {
            imgui.igOpenPopup_Str("RightClickPopup", imgui.ImGuiPopupFlags_None);
        }
        if (imgui.igBeginPopup("RightClickPopup", imgui.ImGuiWindowFlags_None) == true) {
            defer imgui.igEndPopup();
            ImguiUtils.NewEntityComponentPopup(engine_context, entity);
        }
        try EntityImguiRender(entity, engine_context);
    }
}

pub fn OnImguiEvent(self: *ComponentsPanel, event: *ImguiEvent) void {
    switch (event.*) {
        .ET_TogglePanelEvent => self.OnTogglePanelEvent(),
        else => @panic("Response to that event has not been implemented yet in ComponentsPanel!\n"),
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

pub fn OnDeleteEntity(self: *ComponentsPanel, delete_entity: Entity) void {
    if (self.mSelectedEntity) |selected_entity| {
        if (selected_entity.mEntityID == delete_entity.mEntityID) {
            self.mSelectedEntity = null;
        }
    }
}

pub fn OnDeleteScene(self: *ComponentsPanel, delete_scene: SceneLayer) void {
    if (self.mSelectedScene) |selected_scene| {
        if (selected_scene.mSceneID == delete_scene.mSceneID) {
            self.mSelectedScene = null;
        }
    }
}

fn EntityImguiRender(entity: Entity, engine_context: *EngineContext) !void {
    inline for (EntityComponents.ComponentPanelList) |component_type| {
        if (entity.HasComponent(component_type)) {
            try PrintComponent(engine_context, component_type, entity);
        }
    }
}

fn PrintComponent(engine_context: *EngineContext, comptime component_type: type, entity: Entity) !void {
    const tree_flags = imgui.ImGuiTreeNodeFlags_OpenOnArrow;
    const is_tree_open = imgui.igTreeNodeEx_Str(@typeName(component_type), tree_flags);
    if (imgui.igBeginPopupContextItem(@typeName(component_type), imgui.ImGuiPopupFlags_MouseButtonRight)) {
        defer imgui.igEndPopup();

        if (imgui.igMenuItem_Bool("Delete Component", "", false, true)) {
            try engine_context.mImguiEventManager.Insert(engine_context.EngineAllocator(), .{ .ET_RmEntityCompEvent = .{ .mComponent_ptr = entity.GetComponent(component_type).? } });
            entity.RemoveComponent(engine_context.EngineAllocator(), component_type);
        }
    }
    if (is_tree_open) {
        defer imgui.igTreePop();
        const component_ptr = entity.GetComponent(component_type).?;
        try component_ptr.EditorRender(engine_context);
    }
}

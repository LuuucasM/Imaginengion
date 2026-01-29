const std = @import("std");
const imgui = @import("../Core/CImports.zig").imgui;
const EditorWindow = @import("EditorWindow.zig");
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
const AISlotComponent = EntityComponents.AISlotComponent;
const EntityIDComponent = EntityComponents.IDComponent;
const CameraComponent = EntityComponents.CameraComponent;
const ColliderComponent = EntityComponents.ColliderComponent;
const MicComponent = EntityComponents.MicComponent;
const EntityNameComponent = EntityComponents.NameComponent;
const PlayerSlotComponent = EntityComponents.PlayerSlotComponent;
const QuadComponent = EntityComponents.QuadComponent;
const RigidBodyComponent = EntityComponents.RigidBodyComponent;
const TextComponent = EntityComponents.TextComponent;
const TransformComponent = EntityComponents.TransformComponent;
const AudioComponent = EntityComponents.AudioComponent;

const GameObjectUtils = @import("../GameObjects/GameObjectUtils.zig");

const EngineContext = @import("../Core/EngineContext.zig");

const AssetHandle = @import("../Assets/AssetHandle.zig");
const Assets = @import("../Assets/Assets.zig");

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
        var region_size: imgui.ImVec2 = .{ .x = 0, .y = 0 };
        imgui.igGetContentRegionAvail(&region_size);
        if (imgui.igButton("Add Component", .{ .x = region_size.x, .y = 20 }) == true) {
            imgui.igOpenPopup_Str("AddComponent", imgui.ImGuiPopupFlags_None);
        }
        if (imgui.igBeginPopup("AddComponent", imgui.ImGuiWindowFlags_None) == true) {
            defer imgui.igEndPopup();
            inline for (EntityComponents.ComponentsList) |component_type| {
                try self.AddComponentPopupMenu(engine_context, component_type, entity);
            }
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
    inline for (EntityComponents.ComponentsList) |component_type| {
        try ComponentRender(engine_context, component_type, entity);
    }
}

fn ComponentRender(engine_context: *EngineContext, comptime component_type: type, entity: Entity) !void {
    if (entity.HasComponent(component_type)) {
        try PrintComponent(engine_context, component_type, entity);
    }
}

fn PrintComponent(engine_context: *EngineContext, comptime component_type: type, entity: Entity) !void {
    if (imgui.igSelectable_Bool(@typeName(component_type), false, imgui.ImGuiSelectableFlags_None, .{ .x = 0, .y = 0 }) == true) {
        if (component_type.Editable == true) {
            try engine_context.mImguiEventManager.Insert(engine_context.EngineAllocator(), ImguiEvent{
                .ET_SelectComponentEvent = .{ .mEditorWindow = EditorWindow.Init(entity.GetComponent(component_type).?, entity) },
            });
        }
    }
    if (imgui.igBeginPopupContextItem(@typeName(component_type), imgui.ImGuiPopupFlags_MouseButtonRight)) {
        defer imgui.igEndPopup();

        if (imgui.igMenuItem_Bool("Delete Component", "", false, true)) {
            try engine_context.mGameEventManager.Insert(engine_context.EngineAllocator(), .{ .ET_RmEntityCompEvent = .{ .mEntityID = entity.mEntityID, .mComponentType = @enumFromInt(component_type.Ind) } });
            try engine_context.mImguiEventManager.Insert(engine_context.EngineAllocator(), .{ .ET_RmEntityCompEvent = .{ .mComponent_ptr = entity.GetComponent(component_type).? } });
        }
    }
}

fn AddComponentPopupMenu(_: ComponentsPanel, engine_context: *EngineContext, component_type: type, entity: Entity) !void {
    if (!entity.HasComponent(component_type)) {
        if (imgui.igMenuItem_Bool(component_type.Name.ptr, "", false, true)) {
            defer imgui.igCloseCurrentPopup();

            _ = try entity.AddComponent(component_type, null);

            if (component_type == CameraComponent) {
                try AddCameraComponent(engine_context, entity);
            } else if (component_type == QuadComponent) {
                AddQuadComponent(engine_context, entity);
            } else if (component_type == TextComponent) {
                try AddTextComponent(engine_context, entity);
            } else if (component_type == AudioComponent) {
                AddAudioComponent(engine_context, entity);
            }
        }
    }
}

fn AddCameraComponent(engine_context: *EngineContext, entity: Entity) !void {
    const engine_allocator = engine_context.EngineAllocator();
    const new_camera_component = entity.GetComponent(CameraComponent).?;

    new_camera_component.mViewportFrameBuffer = try FrameBuffer.Init(engine_allocator, &[_]TextureFormat{.RGBA8}, .None, 1, false, 1600, 900);
    new_camera_component.mViewportVertexArray = VertexArray.Init();
    new_camera_component.mViewportVertexBuffer = VertexBuffer.Init(@sizeOf([4][2]f32));
    new_camera_component.mViewportIndexBuffer = undefined;

    const shader_asset = engine_context.mRenderer.GetSDFShader();
    try new_camera_component.mViewportVertexBuffer.SetLayout(engine_context.EngineAllocator(), shader_asset.GetLayout());
    new_camera_component.mViewportVertexBuffer.SetStride(shader_asset.GetStride());

    var index_buffer_data = [6]u32{ 0, 1, 2, 2, 3, 0 };
    new_camera_component.mViewportIndexBuffer = IndexBuffer.Init(index_buffer_data[0..], 6);

    var data_vertex_buffer = [4][2]f32{ [2]f32{ -1.0, -1.0 }, [2]f32{ 1.0, -1.0 }, [2]f32{ 1.0, 1.0 }, [2]f32{ -1.0, 1.0 } };
    new_camera_component.mViewportVertexBuffer.SetData(&data_vertex_buffer[0][0], @sizeOf([4][2]f32), 0);
    try new_camera_component.mViewportVertexArray.AddVertexBuffer(engine_allocator, new_camera_component.mViewportVertexBuffer);
    new_camera_component.mViewportVertexArray.SetIndexBuffer(new_camera_component.mViewportIndexBuffer);

    new_camera_component.SetViewportSize(1600, 900);
}

fn AddQuadComponent(engine_context: *EngineContext, entity: Entity) void {
    const new_quad_component = entity.GetComponent(QuadComponent).?;
    new_quad_component.mTexture.mAssetManager = &engine_context.mAssetManager;
}

fn AddTextComponent(engine_context: *EngineContext, entity: Entity) !void {
    const new_text_component = entity.GetComponent(TextComponent).?;
    new_text_component.mTextAssetHandle.mAssetManager = &engine_context.mAssetManager;
    new_text_component.mTexHandle.mAssetManager = &engine_context.mAssetManager;
    try new_text_component.mText.appendSlice(engine_context.EngineAllocator(), "No Text");
}

fn AddAudioComponent(engine_context: *EngineContext, entity: Entity) void {
    const new_audio_component = entity.GetComponent(AudioComponent).?;
    new_audio_component.mAudioAsset.mAssetManager = &engine_context.mAssetManager;
}

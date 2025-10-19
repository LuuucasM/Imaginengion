const std = @import("std");
const imgui = @import("../Core/CImports.zig").imgui;
const ImguiEventManager = @import("../Events/ImguiEventManager.zig");
const GameEventManager = @import("../Events/GameEventManager.zig");
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
const EntityNameComponent = EntityComponents.NameComponent;
const PlayerSlotComponent = EntityComponents.PlayerSlotComponent;
const QuadComponent = EntityComponents.QuadComponent;
const TextComponent = EntityComponents.TextComponent;
const TransformComponent = EntityComponents.TransformComponent;

const AssetManager = @import("../Assets/AssetManager.zig");
const AssetHandle = @import("../Assets/AssetHandle.zig");
const Assets = @import("../Assets/Assets.zig");

const Tracy = @import("../Core/Tracy.zig");

_P_Open: bool = true,
mSelectedScene: ?SceneLayer = null,
mSelectedEntity: ?Entity = null,
mEngineAllocator: std.mem.Allocator = undefined,

pub fn Init(self: *ComponentsPanel, engine_allocator: std.mem.Allocator) void {
    self.mEngineAllocator = engine_allocator;
}

pub fn OnImguiRender(self: ComponentsPanel) !void {
    const zone = Tracy.ZoneInit("Components Panel OIR", @src());
    defer zone.Deinit();

    if (self._P_Open == false) return;

    if (self.mSelectedEntity) |entity| {
        var buffer: [300]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);
        const fba_allocator = fba.allocator();

        const entity_name = entity.GetName();
        const name_len = std.mem.indexOf(u8, entity_name, &.{0}) orelse entity_name.len;
        const trimmed_name = entity_name[0..name_len];
        const name = try std.fmt.allocPrintSentinel(fba_allocator, "Components - {s}###Components\x00", .{trimmed_name}, 0);

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
            try self.AddComponentPopupMenu(entity);
        }
        try EntityImguiRender(entity);
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

fn EntityImguiRender(entity: Entity) !void {
    try ComponentRender(EntityIDComponent, entity);
    try ComponentRender(EntityNameComponent, entity);
    try ComponentRender(TransformComponent, entity);
    try ComponentRender(CameraComponent, entity);
    try ComponentRender(QuadComponent, entity);
    try ComponentRender(AISlotComponent, entity);
    try ComponentRender(PlayerSlotComponent, entity);
    try ComponentRender(TextComponent, entity);
}

fn ComponentRender(comptime component_type: type, entity: Entity) !void {
    if (entity.HasComponent(component_type)) {
        if (component_type.Category == .Unique) {
            //single unique component so we can just get and display component
            try PrintComponent(component_type, entity);
        } else {
            //it is a multi component so we need to get the parents component and then
            //get first and then we can iterate creating a selectable bool for each one
            if (entity.GetComponent(component_type)) |component| {
                var curr_id = component.mFirst;
                //the : (stuff) gets evaluated at the end of the loop so its equivalent to a
                //do-while loop
                while (true) : (if (curr_id == component.mFirst) break) {
                    const component_entity = Entity{ .mEntityID = curr_id, .mECSManagerRef = entity.mECSManagerRef };
                    PrintComponent(component_type, component_entity);

                    const curr_comp = component_entity.GetComponent(component_type).?;
                    curr_id = curr_comp.mNext;
                }
            }
        }
    }
}

fn PrintComponent(comptime component_type: type, entity: Entity) !void {
    if (imgui.igSelectable_Bool(@typeName(component_type), false, imgui.ImGuiSelectableFlags_None, .{ .x = 0, .y = 0 }) == true) {
        if (component_type.Editable == true) {
            try ImguiEventManager.Insert(ImguiEvent{
                .ET_SelectComponentEvent = .{ .mEditorWindow = EditorWindow.Init(entity.GetComponent(component_type).?, entity) },
            });
        }
    }
    if (imgui.igBeginPopupContextItem(@typeName(component_type), imgui.ImGuiPopupFlags_MouseButtonRight)) {
        defer imgui.igEndPopup();

        if (imgui.igMenuItem_Bool("Delete Component", "", false, true)) {
            try GameEventManager.Insert(.{ .ET_RmEntityCompEvent = .{ .mEntityID = entity.mEntityID, .mComponentType = @enumFromInt(component_type.Ind) } });
            try ImguiEventManager.Insert(.{ .ET_RmEntityCompEvent = .{ .mComponent_ptr = entity.GetComponent(component_type).? } });
        }
    }
}

fn AddComponentPopupMenu(self: ComponentsPanel, entity: Entity) !void {
    if (entity.HasComponent(CameraComponent) == false) {
        if (imgui.igMenuItem_Bool("CameraComponent", "", false, true) == true) {
            defer imgui.igCloseCurrentPopup();

            var new_camera_component = CameraComponent{
                .mViewportFrameBuffer = try FrameBuffer.Init(self.mEngineAllocator, &[_]TextureFormat{.RGBA8}, .None, 1, false, 1600, 900),
                .mViewportVertexArray = VertexArray.Init(self.mEngineAllocator),
                .mViewportVertexBuffer = VertexBuffer.Init(self.mEngineAllocator, @sizeOf([4][2]f32)),
                .mViewportIndexBuffer = undefined,
            };

            const shader_asset = try Renderer.GetSDFShader();
            try new_camera_component.mViewportVertexBuffer.SetLayout(shader_asset.GetLayout());
            new_camera_component.mViewportVertexBuffer.SetStride(shader_asset.GetStride());

            var index_buffer_data = [6]u32{ 0, 1, 2, 2, 3, 0 };
            new_camera_component.mViewportIndexBuffer = IndexBuffer.Init(index_buffer_data[0..], 6);

            var data_vertex_buffer = [4][2]f32{ [2]f32{ -1.0, -1.0 }, [2]f32{ 1.0, -1.0 }, [2]f32{ 1.0, 1.0 }, [2]f32{ -1.0, 1.0 } };
            new_camera_component.mViewportVertexBuffer.SetData(&data_vertex_buffer[0][0], @sizeOf([4][2]f32), 0);
            try new_camera_component.mViewportVertexArray.AddVertexBuffer(new_camera_component.mViewportVertexBuffer);
            new_camera_component.mViewportVertexArray.SetIndexBuffer(new_camera_component.mViewportIndexBuffer);

            new_camera_component.SetViewportSize(1600, 900);
            _ = try entity.AddComponent(CameraComponent, new_camera_component);
        }
    }
    if (entity.HasComponent(AISlotComponent) == false) {
        if (imgui.igMenuItem_Bool("AISlotComponent", "", false, true) == true) {
            defer imgui.igCloseCurrentPopup();
            _ = try entity.AddComponent(AISlotComponent, null);
        }
    }
    if (entity.HasComponent(PlayerSlotComponent) == false) {
        if (imgui.igMenuItem_Bool("PlayerSlotComponent", "", false, true) == true) {
            defer imgui.igCloseCurrentPopup();
            _ = try entity.AddComponent(PlayerSlotComponent, null);
        }
    }
    if (entity.HasComponent(QuadComponent) == false) {
        if (imgui.igMenuItem_Bool("QuadComponent", "", false, true) == true) {
            defer imgui.igCloseCurrentPopup();
            const new_sprite_component = try entity.AddComponent(QuadComponent, null);
            new_sprite_component.mTexture = try AssetManager.GetAssetHandleRef("assets/textures/whitetexture.png", .Eng);
        }
    }
    if (entity.HasComponent(TextComponent) == false) {
        if (imgui.igMenuItem_Bool("TextComponent", "", false, true)) {
            defer imgui.igCloseCurrentPopup();
            const new_text_component = try entity.AddComponent(TextComponent, null);
            new_text_component.mTextAssetHandle = try AssetManager.GetAssetHandleRef("assets/fonts/Chiron/static/ChironGoRoundTC-Regular.ttf", .Eng);
            new_text_component.mAtlasHandle = try AssetManager.GetAssetHandleRef("assets/fonts/Chiron/static/ChironGoRoundTC-Regular.png", .Eng);
            new_text_component.mTexHandle = try AssetManager.GetAssetHandleRef("assets/textures/whitetexture.png", .Eng);
            new_text_component.mAllocator = entity.GetECSAllocator();
            try new_text_component.mText.appendSlice(new_text_component.mAllocator, "No Text");
        }
    }
}

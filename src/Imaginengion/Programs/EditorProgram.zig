const std = @import("std");

const Window = @import("../Windows/Window.zig");
const ScriptsProcessor = @import("../Scripts/ScriptsProcessor.zig");
const Renderer = @import("../Renderer/Renderer.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../GameObjects/Entity.zig");
const VertexArray = @import("../VertexArrays/VertexArray.zig");
const VertexBuffer = @import("../VertexBuffers/VertexBuffer.zig");
const PlayerManager = @import("../Players/PlayerManager.zig");
const Player = @import("../Players/Player.zig");
const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;
const AssetHandle = @import("../Assets/AssetHandle.zig");
const imgui = @import("../Core/CImports.zig").imgui;
const PlatformUtils = @import("../PlatformUtils/PlatformUtils.zig");

const Assets = @import("../Assets/Assets.zig");
const AudioAsset = Assets.AudioAsset;

const LinAlg = @import("../Math/LinAlg.zig");
const Vec3f32 = LinAlg.Vec3f32;
const Quatf32 = LinAlg.Quatf32;
const Vec4f32 = LinAlg.Vec4f32;

const EntityComponents = @import("../GameObjects/Components.zig");
const TransformComponent = EntityComponents.TransformComponent;
const EntityUUIDComponent = EntityComponents.UUIDComponent;
const OnInputPressedScript = EntityComponents.OnInputPressedScript;
const OnUpdateScript = EntityComponents.OnUpdateScript;
const PlayerSlotComponent = EntityComponents.PlayerSlotComponent;
const GameObjectUtils = @import("../GameObjects/GameObjectUtils.zig");

const SceneComponents = @import("../Scene/SceneComponents.zig");
const SceneComponent = SceneComponents.SceneComponent;
const OnSceneStartScript = SceneComponents.OnSceneStartScript;

const PlayerComponents = @import("../Players/Components.zig");
const PossessComponent = PlayerComponents.PossessComponent;
const PlayerLens = PlayerComponents.LensComponent;

const SystemEvent = @import("../Events/SystemEvent.zig").SystemEvent;
const InputPressedEvent = @import("../Events/SystemEvent.zig").InputPressedEvent;
const WindowResizeEvent = @import("../Events/SystemEvent.zig").WindowResizeEvent;
const ImguiEvent = @import("../Events/ImguiEvent.zig").ImguiEvent;
const ImguiEventManager = @import("../Events/ImguiEventManager.zig");
const GameEvent = @import("../Events/GameEvent.zig").GameEvent;
const ChangeEditorStateEvent = @import("../Events/ImguiEvent.zig").ChangeEditorStateEvent;

const ImGui = @import("../Imgui/Imgui.zig");
const Dockspace = @import("../Imgui/Dockspace.zig");
const AssetHandlePanel = @import("../Imgui/AssethandlePanel.zig");
const ComponentsPanel = @import("../Imgui/ComponentsPanel.zig");
const ContentBrowserPanel = @import("../Imgui/ContentBrowserPanel.zig");
const CSEditorPanel = @import("../Imgui/CSEditorPanel.zig");
const ScenePanel = @import("../Imgui/ScenePanel.zig");
const ScriptsPanel = @import("../Imgui/ScriptsPanel.zig");
const StatsPanel = @import("../Imgui/StatsPanel.zig");
const ToolbarPanel = @import("../Imgui/ToolbarPanel.zig");
const ViewportPanel = @import("../Imgui/ViewportPanel.zig");
const SceneSpecPanel = @import("../Imgui/SceneSpecsPanel.zig");

const SceneManager = @import("../Scene/SceneManager.zig");
const SceneLayer = @import("../Scene/SceneLayer.zig");
const EditorState = @import("../Imgui/ToolbarPanel.zig").EditorState;
const FrameBuffer = @import("../FrameBuffers/FrameBuffer.zig");
const TextureFormat = @import("../FrameBuffers/InternalFrameBuffer.zig").TextureFormat;
const IndexBuffer = @import("../IndexBuffers/IndexBuffer.zig");
const EditorProgram = @This();
const Tracy = @import("../Core/Tracy.zig");

pub const PanelOpen = struct {
    mAssetHandlePanel: bool,
    mCSEditorPanel: bool,
    mComponentsPanel: bool,
    mContentBrowserPanel: bool,
    mScenePanel: bool,
    mScriptsPanel: bool,
    mStatsPanel: bool,
    mViewportPanel: bool,
    mPreviewPanel: bool,
};

//editor imgui stuff
_AssetHandlePanel: AssetHandlePanel = .{},
_ComponentsPanel: ComponentsPanel = .{},
_ContentBrowserPanel: ContentBrowserPanel = .{},
_CSEditorPanel: CSEditorPanel = .{},
_ScenePanel: ScenePanel = .{},
_ScriptsPanel: ScriptsPanel = .{},
_StatsPanel: StatsPanel = .{},
_ToolbarPanel: ToolbarPanel = .{},
_ViewportPanel: ViewportPanel = .{},
_SceneSpecList: std.ArrayList(SceneSpecPanel) = .{},

//editor UI stuff
mEditorUIScene: SceneLayer = .{},
mEditorUIEntity: Entity = .{},
mEditorUIPlayer: Player = .{},

//Editor viewport stuff
mEditorViewportScene: SceneLayer = .{},
mEditorViewportEntity: Entity = .{},
mEditorViewportPlayer: Player = .{},

//misc stuff
mEditorFont: AssetHandle = .{},
mImgui: ImGui = .{},
mActiveWindowWorld: *SceneManager = undefined,
mActiveViewportWorld: *SceneManager = undefined,
mActiveSimulateWorld: *SceneManager = undefined,

pub fn Init(self: *EditorProgram, engine_context: *EngineContext) !void {
    const engine_allocator = engine_context.EngineAllocator();

    try self.mImgui.Init(engine_context.mAppWindow);

    self._ComponentsPanel.Init();
    try self._ContentBrowserPanel.Init(engine_context);
    self._CSEditorPanel.Init(engine_allocator);
    try self._ToolbarPanel.Init(engine_context);
    self._ViewportPanel.Init(engine_context.mAppWindow.GetWidth(), engine_context.mAppWindow.GetHeight());

    self.mEditorUIScene = try engine_context.mEditorWorld.NewScene(engine_context, .OverlayLayer);
    self.mEditorUIEntity = try self.mEditorUIScene.CreateEntity(engine_allocator);
    self.mEditorUIPlayer = engine_context.mEditorWorld.CreatePlayer(engine_context);

    self.mEditorViewportScene = try engine_context.mEditorWorld.NewScene(engine_context, .GameLayer);
    self.mEditorViewportEntity = try self.mEditorViewportScene.CreateEntity(engine_allocator);
    self.mEditorViewportPlayer = engine_context.mEditorWorld.CreatePlayer(engine_context);

    self.mEditorUIEntity.GetComponent(TransformComponent).?.Translation = Vec3f32{ 0.0, 0.0, 15.0 };
    self.mEditorViewportEntity.GetComponent(TransformComponent).?.Translation = Vec3f32{ 0.0, 0.0, 15.0 };

    try self.mEditorViewportEntity.AddComponentScript(engine_context, self.mEditorViewportEntity, "assets/scripts/EditorCameraInput.zig", .Eng);

    self.mEditorUIPlayer.GetComponent(PlayerLens).?.SetViewportSize(engine_context.mAppWindow.GetWidth(), engine_context.mAppWindow.GetHeight());
    self.mEditorViewportPlayer.GetComponent(PlayerLens).?.SetViewportSize(self._ViewportPanel.mViewportWidth, self._ViewportPanel.mViewportHeight);

    try self.mEditorViewportEntity.AddComponent(PlayerSlotComponent{});
    self.mEditorViewportEntity.Possess(self.mEditorViewportPlayer);
    self.mEditorViewportPlayer.Possess(self.mEditorViewportEntity);

    try self.mEditorUIEntity.AddComponent(PlayerSlotComponent{});
    self.mEditorUIEntity.Possess(self.mEditorUIPlayer);
    self.mEditorUIPlayer.Possess(self.mEditorUIEntity);

    self.mActiveWindowWorld = &engine_context.mEditorWorld;
    self.mActiveViewportWorld = &engine_context.mGameWorld;
    self.mActiveSimulateWorld = &engine_context.mSimulateWorld;
}

pub fn Deinit(self: *EditorProgram, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("EditorProgram::Deinit", @src());
    defer zone.Deinit();

    self._ContentBrowserPanel.Deinit(engine_context);
    self._CSEditorPanel.Deinit();
    self.mImgui.Deinit();
}

//Note other systems to consider in the on update loop
//that isnt there already:
//particles
//handling the loading and unloading of assets and scene transitions
//debug/profiling
pub fn OnUpdate(self: *EditorProgram, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("Program OnUpdate", @src());
    defer zone.Deinit();

    const engine_allocator = engine_context.EngineAllocator();

    //--------------Incoming network packets
    {
        const input_zone = Tracy.ZoneInit("Incoming Network Section", @src());
        defer input_zone.Deinit();
    }
    //==============End Incoming Network packets

    //-------------Inputs Begin------------------
    {
        const input_zone = Tracy.ZoneInit("Inputs Section", @src());
        defer input_zone.Deinit();

        //Human Inputs
        engine_context.mAppWindow.PollInputEvents();
        try engine_context.mSystemEventManager.ProcessEvents(engine_context, .EC_Input);

        //AI Inputs
    }
    //---------------Inputs End-------------------

    //-------------Physics Begin-----------------
    {
        const physics_zone = Tracy.ZoneInit("Physics Section", @src());
        defer physics_zone.Deinit();
        if (self._ToolbarPanel.mState == .Play) {
            try engine_context.mPhysicsManager.OnUpdate(engine_context, .Simulate);
        }
    }
    //-------------Physics End-------------------

    //-------------Game Logic Begin--------------
    {
        const game_logic_zone = Tracy.ZoneInit("Game Logic Section", @src());
        defer game_logic_zone.Deinit();

        if (self._ToolbarPanel.mState == .Play) {
            _ = try ScriptsProcessor.RunEntityScript(OnUpdateScript, .Simulate, engine_context, .{});
        }
        _ = try ScriptsProcessor.RunEntityScript(OnUpdateScript, .Editor, engine_context, .{});
    }
    //-------------Game Logic End----------------

    //-------------Animation Begin--------------
    {
        const animation_zone = Tracy.ZoneInit("Animation Section", @src());
        defer animation_zone.Deinit();
    }
    //-------------Animation End----------------

    //-------------Assets update Begin---------------
    {
        const assets_zone = Tracy.ZoneInit("Assets Section", @src());
        defer assets_zone.Deinit();
        try engine_context.mAssetManager.OnUpdate(engine_context);
    }
    //-------------End Assets Update ------------------

    //--------------World Transform Update --------------
    {
        const assets_zone = Tracy.ZoneInit("World Transform Update Section", @src());
        defer assets_zone.Deinit();
        try engine_context.mPhysicsManager.UpdateWorldTransforms(.Game, engine_context);
        try engine_context.mPhysicsManager.UpdateWorldTransforms(.Editor, engine_context);
        if (self._ToolbarPanel.mState == .Play) {
            try engine_context.mPhysicsManager.UpdateWorldTransforms(.Simulate, engine_context);
        }
    }
    //---------------End World Transform Update ------------

    //---------Render Begin-------------
    {
        const render_zone = Tracy.ZoneInit("Render Section", @src());
        defer render_zone.Deinit();
        if (engine_context.mIsMinimized == false) {
            self.mImgui.Begin();
            Dockspace.Begin();

            try self._ContentBrowserPanel.OnImguiRender(engine_context);
            try self._AssetHandlePanel.OnImguiRender(engine_context);
            try self._ScenePanel.OnImguiRender(.Editor, engine_context);
            for (self._SceneSpecList.items) |*scene_spec_panel| {
                try scene_spec_panel.OnImguiRender(engine_context);
            }

            try self._ComponentsPanel.OnImguiRender(engine_context);
            try self._ScriptsPanel.OnImguiRender(engine_context);
            try self._CSEditorPanel.OnImguiRender(engine_context);

            try self.RenderViewportSimLens(engine_context);
            try self.DisplayViewSimPort(engine_context);

            try self._StatsPanel.OnImguiRender(engine_context.mDT, engine_context.mRenderer.GetRenderStats());

            try self._ToolbarPanel.OnImguiRender(.Game, engine_context);

            try self.DockspaceOnImguiRender(engine_context, self);

            try engine_context.mImguiEventManager.ProcessEvents(engine_context);

            Dockspace.End();
            self.mImgui.End();
        }
    }
    //--------------Render End-------------------

    //--------------Audio Begin------------------
    {
        const audio_zone = Tracy.ZoneInit("Audio Section", @src());
        defer audio_zone.Deinit();
    }
    //--------------Audio End--------------------

    //--------------Outgoing Networking Begin-------------
    {
        const networking_zone = Tracy.ZoneInit("Outgoing Network Section", @src());
        defer networking_zone.Deinit();
    }
    //--------------Outgoing Networking End---------------

    //-----------------Start End of Frame-----------------
    {
        const end_frame_zone = Tracy.ZoneInit("End Frame Section", @src());
        defer end_frame_zone.Deinit();

        //swap buffers
        engine_context.mRenderer.SwapBuffers();

        //Process window events
        try engine_context.mSystemEventManager.ProcessEvents(engine_context, .EC_Window);

        //handle any closed scene spec panels
        self.CleanSceneSpecs(engine_context.EngineAllocator());

        //handle deleted objects this frame
        try engine_context.mGameEventManager.ProcessEvents(engine_context, .EC_EndOfFrame);

        try engine_context.mGameWorld.ProcessRemovedObj(engine_context);
        try engine_context.mEditorWorld.ProcessRemovedObj(engine_context);
        try engine_context.mSimulateWorld.ProcessRemovedObj(engine_context);

        try engine_context.mAssetManager.ProcessDestroyedAssets(engine_context);

        //end of frame resets
        engine_context.mSystemEventManager.EventsReset(engine_allocator, .ClearRetainingCapacity);
        engine_context.mGameEventManager.EventsReset(engine_allocator, .ClearRetainingCapacity);
        engine_context.mImguiEventManager.EventsReset(engine_allocator, .ClearRetainingCapacity);
    }
    //-----------------End End of Frame-------------------

}

pub fn OnImguiEvent(self: *EditorProgram, event: *ImguiEvent, engine_context: *EngineContext) !void {
    switch (event.*) {
        .ET_MoveSceneEvent => |e| {
            try engine_context.mGameWorld.MoveScene(engine_context.FrameAllocator(), e.SceneID, e.NewPos);
        },
        .ET_SelectSceneEvent => |e| {
            self._ScenePanel.OnSelectSceneEvent(e.SelectedScene);
            self._ComponentsPanel.OnSelectSceneEvent(e.SelectedScene);
        },
        .ET_SelectEntityEvent => |e| {
            self._ScenePanel.OnSelectEntityEvent(e.SelectedEntity);
            self._ComponentsPanel.OnSelectEntityEvent(e.SelectedEntity);
            self._ScriptsPanel.OnSelectEntityEvent(e.SelectedEntity);
            self._ViewportPanel.OnSelectEntityEvent(e.SelectedEntity);
        },
        .ET_ViewportResizeEvent => |e| {
            self.mActiveViewportWorld.OnViewportResize(engine_context.FrameAllocator(), e.mWidth, e.mHeight);
        },
        .ET_PlayPanelResizeEvent => |e| {
            self.mActiveSimulateWorld.OnViewportResize(engine_context.FrameAllocator(), e.mWidth, e.mHeight);
        },
        .ET_ChangeEditorStateEvent => |e| {
            try self.OnChangeEditorStateEvent(engine_context, e);
        },
        .ET_OpenSceneSpecEvent => |e| {
            const new_scene_spec_panel = try SceneSpecPanel.Init(e.mSceneLayer);
            try self._SceneSpecList.append(engine_context.EngineAllocator(), new_scene_spec_panel);
        },
        .ET_DeleteEntityEvent => |e| {
            self._ScenePanel.OnDeleteEntity(e.mEntity);
            self._ComponentsPanel.OnDeleteEntity(e.mEntity);
            self._ScriptsPanel.OnDeleteEntity(e.mEntity);
            self._ViewportPanel.OnDeleteEntity(e.mEntity);
        },
        .ET_DeleteSceneEvent => |e| {
            self._ScenePanel.OnDeleteScene(e.mScene);
            self._ComponentsPanel.OnDeleteScene(e.mScene);
        },
        else => std.debug.print("This event has not been handled by editor program!\n", .{}),
    }
}

pub fn OnChangeEditorStateEvent(self: *EditorProgram, engine_context: *EngineContext, event: ChangeEditorStateEvent) !void {
    if (event.mEditorState == .Play) { //the play button was pressed
        try engine_context.mGameWorld.Copy(engine_context, engine_context.mSimulateWorld);
        const new_player = try engine_context.mSimulateWorld.CreatePlayer(engine_context);
        self._ToolbarPanel.mStartDescriptor.?.Possess(new_player);

        self.mActiveViewportWorld = &engine_context.mSimulateWorld;
        self.mActiveSimulateWorld = &engine_context.mGameWorld;
    } else {
        //stop button was pressed
        self.mActiveViewportWorld = &engine_context.mGameWorld;
        self.mActiveSimulateWorld = &engine_context.mSimulateWorld;
    }
}

pub fn OnInputPressedEvent(self: *EditorProgram, engine_context: *EngineContext, e: InputPressedEvent) !bool {
    _ = try ScriptsProcessor.RunEntityScript(OnInputPressedEvent, .Editor, engine_context, .{&e});
    //scene on input script probably need to add TODO

    if (self._ToolbarPanel.mState == .Play) {
        _ = try ScriptsProcessor.RunEntityScript(OnInputPressedScript, .Simulate, engine_context, .{&e});
    }

    _ = self._ViewportPanel.OnInputPressedEvent(e);

    return true;
}

fn CleanSceneSpecs(self: *EditorProgram, engine_allocator: std.mem.Allocator) void {
    const zone = Tracy.ZoneInit("Clean Scene Specs", @src());
    defer zone.Deinit();
    var end_index: usize = self._SceneSpecList.items.len;
    var i: usize = 0;

    while (i < end_index) {
        if (self._SceneSpecList.items[i].mPOpen == false) {
            self._SceneSpecList.items[i] = self._SceneSpecList.items[end_index - 1];
            end_index -= 1;
        } else {
            i += 1;
        }
    }
    self._SceneSpecList.shrinkAndFree(engine_allocator, end_index);
}

fn RenderViewportSimLens(self: *EditorProgram, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("RenderViewportSimLens", @src());
    defer zone.Deinit();
    if (self._ViewportPanel.mP_OpenPlay) {
        self.RenderViewportLens(engine_context);
        if (self._ToolbarPanel.mState == .Stop) {
            self.RenderPlayerLens(.Game, engine_context);
        } else {
            self.RenderPlayerLens(.Simulate, engine_context);
        }
    } else { //only have the viewport panel no simulate panel
        if (self._ToolbarPanel.mState == .Stop) {
            self.RenderViewportLens(engine_context);
        } else {
            self.RenderPlayerLens(.Simulate, engine_context);
        }
    }
}

fn RenderViewportLens(self: *EditorProgram, engine_context: *EngineContext) !void {
    const lens_component = self.mEditorViewportPlayer.GetComponent(PlayerLens).?;
    const transform_component = self.mEditorViewportEntity.GetComponent(TransformComponent).?;
    const world_rot = transform_component.GetWorldRotation();
    const world_pos = transform_component.GetWorldPosition();
    const lens_offset_pos = lens_component.OffsetPosition;
    const lens_offset_rot = lens_component.OffsetRotation;
    const final_rot = LinAlg.QuatMulQuat(world_rot, lens_offset_rot);
    const final_pos = Vec3f32{ world_pos[0] + lens_offset_pos[0], world_pos[1] + lens_offset_pos[1], world_pos[2] + lens_offset_pos[2] };

    try engine_context.mRenderer.OnUpdate(
        .Game,
        engine_context,
        .{
            .mRotation = [4]f32{ final_rot[0], final_rot[1], final_rot[2], final_rot[3] }, //this is in (w, x, y, z) format
            .mPosition = [3]f32{ final_pos[0], final_pos[1], final_pos[2] }, //this is in (x, y, z) format
            .mPerspectiveFar = lens_component.mPerspectiveFar,
            .mResolutionWidth = @floatFromInt(lens_component.mViewportWidth),
            .mResolutionHeight = @floatFromInt(lens_component.mViewportHeight),
            .mAspectRatio = lens_component.mAspectRatio,
            .mFOV = lens_component.mPerspectiveFOVRad,
        },
        .{
            .FrameBuffer = lens_component.mViewportFrameBuffer,
            .VertexArray = lens_component.mViewportVertexArray,
            .VertexBuffer = lens_component.mViewportVertexBuffer,
        },
        0b1,
    );
}

fn RenderPlayerLens(_: *EditorProgram, comptime world_type: EngineContext.WorldType, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("Render Bufferss", @src());
    defer zone.Deinit();

    const scene_manager = switch (world_type) {
        .Game => engine_context.mGameWorld,
        .Editor => engine_context.mEditorWorld,
        .Simulate => engine_context.mSimulateWorld,
    };

    const frame_allocator = engine_context.FrameAllocator();

    const player_slot_entities = scene_manager.GetEntityGroup(frame_allocator, .{ .Component = PlayerSlotComponent });
    FilterPossessedEntities(frame_allocator, player_slot_entities, scene_manager);

    for (player_slot_entities) |entity_id| {
        const entity = scene_manager.GetEntity(entity_id);
        const slot_component = entity.GetComponent(PlayerSlotComponent).?;
        const lens_component = slot_component.mPlayerEntity.?.GetComponent(PlayerLens).?;
        const transform_component = entity.GetComponent(TransformComponent).?;

        const world_rot = transform_component.GetWorldRotation();
        const world_pos = transform_component.GetWorldPosition();
        const lens_offset_pos = lens_component.OffsetPosition;
        const lens_offset_rot = lens_component.OffsetRotation;

        const final_rot = LinAlg.QuatMulQuat(world_rot, lens_offset_rot);
        const final_pos = Vec3f32{ world_pos[0] + lens_offset_pos[0], world_pos[1] + lens_offset_pos[1], world_pos[2] + lens_offset_pos[2] };

        try engine_context.mRenderer.OnUpdate(
            engine_context,
            scene_manager,
            .{
                .mRotation = [4]f32{ final_rot[0], final_rot[1], final_rot[2], final_rot[3] }, //this is in (w, x, y, z) format
                .mPosition = [3]f32{ final_pos[0], final_pos[1], final_pos[2] }, //this is in (x, y, z) format
                .mPerspectiveFar = lens_component.mPerspectiveFar,
                .mResolutionWidth = @floatFromInt(lens_component.mViewportWidth),
                .mResolutionHeight = @floatFromInt(lens_component.mViewportHeight),
                .mAspectRatio = lens_component.mAspectRatio,
                .mFOV = lens_component.mPerspectiveFOVRad,
            },
            .{
                .FrameBuffer = lens_component.mViewportFrameBuffer,
                .VertexArray = lens_component.mViewportVertexArray,
                .VertexBuffer = lens_component.mViewportVertexBuffer,
            },
            0b1,
        );
    }
}

fn DisplayViewSimPort(self: *EditorProgram, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("DisplayViewSimPort", @src());
    defer zone.Deinit();
    const frame_allocator = engine_context.FrameAllocator();
    var viewport_framebuffers = std.ArrayList(FrameBuffer){};
    var viewport_area_rects = std.ArrayList(Vec4f32){};
    if (self._ViewportPanel.mP_OpenPlay) {
        if (self._ToolbarPanel.mState == .Stop) {
            self.DisplayViewportBuffs(frame_allocator, viewport_framebuffers, viewport_area_rects);
            self._ViewportPanel.OnImguiRenderViewport(engine_context, viewport_framebuffers, viewport_area_rects);

            viewport_framebuffers.clearRetainingCapacity();
            viewport_area_rects.clearRetainingCapacity();

            self.DisplayPlayerBuffs(.Game, engine_context, viewport_framebuffers, viewport_area_rects);
            self._ViewportPanel.OnImguiRenderPlay(engine_context, viewport_framebuffers, viewport_area_rects);
        } else {
            self.DisplayPlayerBuffs(.Simulate, engine_context, viewport_framebuffers, viewport_area_rects);
            self._ViewportPanel.OnImguiRenderViewport(engine_context, viewport_framebuffers, viewport_area_rects);

            viewport_framebuffers.clearRetainingCapacity();
            viewport_area_rects.clearRetainingCapacity();

            self.DisplayViewportBuffs(frame_allocator, viewport_framebuffers, viewport_area_rects);
            self._ViewportPanel.OnImguiRenderPlay(engine_context, viewport_framebuffers, viewport_area_rects);
        }
    } else {
        if (self._ToolbarPanel.mState == .Stop) {
            self.DisplayViewportBuffs(frame_allocator, viewport_framebuffers, viewport_area_rects);
            self._ViewportPanel.OnImguiRenderViewport(engine_context, viewport_framebuffers, viewport_area_rects);
        } else {
            self.DisplayPlayerBuffs(.Simulate, engine_context, viewport_framebuffers, viewport_area_rects);
            self._ViewportPanel.OnImguiRenderViewport(engine_context, viewport_framebuffers, viewport_area_rects);
        }
    }
}

fn DisplayViewportBuffs(self: *EditorProgram, frame_allocator: std.mem.Allocator, viewport_framebuffers: *std.ArrayList(FrameBuffer), viewport_area_rects: *std.ArrayList(Vec4f32)) !void {
    const lens_component = self.mEditorViewportPlayer.GetComponent(PlayerLens).?;
    viewport_framebuffers.append(frame_allocator, lens_component.mFrameBuffer);
    viewport_area_rects.append(frame_allocator, lens_component.mAreaRect);
}

fn DisplayPlayerBuffs(_: *EditorProgram, comptime world_type: EngineContext.WorldType, engine_context: *EngineContext, viewport_framebuffers: *std.ArrayList(FrameBuffer), viewport_area_rects: *std.ArrayList(Vec4f32)) !void {
    const frame_allocator = engine_context.FrameAllocator();
    const scene_manager = switch (world_type) {
        .Game => engine_context.mGameWorld,
        .Editor => engine_context.mEditorWorld,
        .Simulate => engine_context.mSimulateWorld,
    };
    const player_slot_entities = scene_manager.GetEntityGroup(frame_allocator, .{ .Component = PlayerSlotComponent });
    FilterPossessedEntities(frame_allocator, player_slot_entities, scene_manager);
    for (player_slot_entities) |entity_id| {
        const entity = scene_manager.GetEntity(entity_id);
        const slot_component = entity.GetComponent(PlayerSlotComponent).?;
        const player = slot_component.mPlayerEntity.?;
        const lens_component = player.GetComponent(PlayerLens);
        viewport_framebuffers.append(frame_allocator, lens_component.mFrameBuffer);
        viewport_area_rects.append(frame_allocator, lens_component.mAreaRect);
    }
}

fn FilterPossessedEntities(frame_allocator: std.mem.Allocator, player_slot_entities: *std.ArrayList(Entity.Type), scene_manager: *SceneManager) !void {
    var start: usize = 0;
    var end: usize = 0;

    while (start < end) {
        const entity = scene_manager.GetEntity(player_slot_entities.items[start]);
        const player_slot_component = entity.GetComponent(PlayerSlotComponent).?;
        if (player_slot_component.mPlayerEntity) |player| {
            if (player.mEntityID != Player.NullPlayer) {
                start += 1;
            } else {
                player_slot_entities.items[start] = player_slot_entities.items[end - 1];
                end -= 1;
            }
        } else {
            player_slot_entities.items[start] = player_slot_entities.items[end - 1];
            end -= 1;
        }
    }

    player_slot_entities.shrinkAndFree(frame_allocator, end);
}

pub fn OnImguiRender(self: *EditorProgram, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("Dockspace OIR", @src());
    defer zone.Deinit();

    const engine_allocator = engine_context.EngineAllocator();

    const my_null_ptr: ?*anyopaque = null;
    if (imgui.igBeginMenuBar() == true) {
        defer imgui.igEndMenuBar();
        if (imgui.igBeginMenu("File", true) == true) {
            defer imgui.igEndMenu();
            if (imgui.igBeginMenu("New Scene", true) == true) {
                defer imgui.igEndMenu();
                if (imgui.igMenuItem_Bool("New Game Scene", "", false, true) == true) {
                    _ = try engine_context.mGameWorld.NewScene(engine_context, .GameLayer);
                }
                if (imgui.igMenuItem_Bool("New Overlay Scene", "", false, true) == true) {
                    _ = try engine_context.mGameWorld.NewScene(engine_context, .OverlayLayer);
                }
            }
            if (imgui.igMenuItem_Bool("Open Scene", "", false, true) == true) {
                const path = try PlatformUtils.OpenFile(engine_allocator, ".imsc");
                if (path > 0) {
                    _ = try engine_context.mGameWorld.LoadScene(engine_context, path);
                }
            }
            if (imgui.igMenuItem_Bool("Save Scene", "", false, true) == true) {
                if (self._ScenePanel.mSelectedScene) |scene_layer| {
                    try engine_context.mGameWorld.SaveScene(engine_context, scene_layer);
                }
            }
            if (imgui.igMenuItem_Bool("Save Scene As...", "", false, true) == true) {
                if (self._ScenePanel.mSelectedScene) |scene_layer| {
                    try engine_context.mGameWorld.SaveSceneAs(engine_context.FrameAllocator(), scene_layer);
                }
            }
            imgui.igSeparator();
            if (imgui.igMenuItem_Bool("Save Entity", "", false, true)) {
                if (self._ScenePanel.mSelectedEntity) |selected_entity| {
                    try engine_context.mGameWorld.SaveEntity(engine_context.FrameAllocator(), selected_entity);
                }
            }
            if (imgui.igMenuItem_Bool("Save Entity As...", "", false, true)) {
                if (self._ScenePanel.mSelectedEntity) |selected_entity| {
                    try engine_context.mGameWorld.SaveEntityAs(engine_context.FrameAllocator(), selected_entity);
                }
            }
            imgui.igSeparator();
            if (imgui.igMenuItem_Bool("New Project", "", false, true) == true) {
                const abs_path = try PlatformUtils.OpenFolder(engine_context.FrameAllocator());
                if (abs_path > 0) {
                    try self._ContentBrowserPanel.OnNewProjectEvent(engine_allocator, abs_path);
                    try engine_context.mAssetManager.OnNewProjectEvent(engine_allocator, abs_path);
                }
            }
            if (imgui.igMenuItem_Bool("Open Project", "", false, true) == true) {
                const abs_path = try PlatformUtils.OpenFile(engine_context.EngineAllocator(), ".imprj");
                if (abs_path > 0) {
                    try self._ContentBrowserPanel.OnOpenProjectEvent(engine_allocator, abs_path);
                    try engine_context.mAssetManager.OnOpenProjectEvent(engine_allocator, abs_path);
                }
            }
            imgui.igSeparator();
            if (imgui.igMenuItem_Bool("Exit", @ptrCast(@alignCast(my_null_ptr)), false, true) == true) {
                const new_event = SystemEvent{
                    .ET_WindowClose = .{},
                };
                try engine_context.mSystemEventManager.Insert(engine_allocator, new_event);
            }
        }
        if (imgui.igBeginMenu("Window", true) == true) {
            defer imgui.igEndMenu();
            if (imgui.igMenuItem_Bool("Asset Handles", @ptrCast(@alignCast(my_null_ptr)), self._AssetHandlePanel._P_Open, true) == true) {
                const new_event = ImguiEvent{
                    .ET_TogglePanelEvent = .{
                        ._PanelType = .AssetHandles,
                    },
                };
                try engine_context.mImguiEventManager.Insert(engine_allocator, new_event);
            }
            if (imgui.igMenuItem_Bool("Components", @ptrCast(@alignCast(my_null_ptr)), self._ComponentsPanel._P_Open, true) == true) {
                self._ComponentsPanel._P_Open = !self._ComponentsPanel._P_Open;
            }
            if (imgui.igMenuItem_Bool("Content Browser", @ptrCast(@alignCast(my_null_ptr)), self._ContentBrowserPanel.mIsVisible, true) == true) {
                self._ContentBrowserPanel.mIsVisible = !self._ContentBrowserPanel.mIsVisible;
            }
            if (imgui.igMenuItem_Bool("Component/Script Editor", @ptrCast(@alignCast(my_null_ptr)), self._CSEditorPanel.mP_Open, true) == true) {
                self._CSEditorPanel.mP_Open = !self._CSEditorPanel.mP_Open;
            }
            if (imgui.igMenuItem_Bool("Scene", @ptrCast(@alignCast(my_null_ptr)), self._ScenePanel.mIsVisible, true) == true) {
                self._ScenePanel.mIsVisible = !self._ScenePanel.mIsVisible;
            }
            if (imgui.igMenuItem_Bool("Scripts", @ptrCast(@alignCast(my_null_ptr)), self._ScriptsPanel._P_Open, true) == true) {
                self._ScriptsPanel._P_Open = !self._ScriptsPanel._P_Open;
            }
            if (imgui.igMenuItem_Bool("Stats", @ptrCast(@alignCast(my_null_ptr)), self._StatsPanel._P_Open, true) == true) {
                self._StatsPanel._P_Open = !self._StatsPanel._P_Open;
            }
            if (imgui.igMenuItem_Bool("Viewport", @ptrCast(@alignCast(my_null_ptr)), self._ViewportPanel.mP_OpenViewport, true) == true) {
                self._ViewportPanel.mP_OpenViewport = !self._ViewportPanel.mP_OpenViewport;
            }
        }
        if (imgui.igBeginMenu("Editor", true) == true) {
            defer imgui.igEndMenu();
            if (imgui.igMenuItem_Bool("Use Preview Panel", @ptrCast(@alignCast(my_null_ptr)), self._ViewportPanel.mP_OpenPlay, true) == true) {
                self._ViewportPanel.mP_OpenPlay = !self._ViewportPanel.mP_OpenPlay;
            }
        }
    }
}

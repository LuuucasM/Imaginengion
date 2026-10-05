//! A window for editing one template: its tree, a preview of it, and the selected object's components side by side, a
//! Save button, and an X that saves and closes. The template is loaded from its file into its own scene in
//! EngineContext.mTmplEditWorld, where nothing runs, and written back to the same file. The editor keeps one of these
//! per open template.
const std = @import("std");
const imgui = @import("../Core/CImports.zig").imgui;
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const RenderStats = @import("../Core/EngineStats.zig").RenderStats;
const Renderer = @import("../Renderer/Renderer.zig");
const ComputeOutput = Renderer.ComputeOutput;
const AssetHandle = @import("../ECSObjects/AssetHandle.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const Scene = @import("../ECSObjects/Scene.zig");
const Player = @import("../ECSObjects/Player.zig");
const GameContext = @import("../ECSObjects/GameContext.zig");
const SelectedObject = @import("../Programs/EditorProgram.zig").SelectedObject;
const Serializer = @import("../Serializer/Serializer.zig");
const TextSerializer = @import("../Serializer/TextSerializer.zig");
const ECSDisplay = @import("ECSDisplay.zig");
const ComponentsPanel = @import("ComponentsPanel.zig");
const GroupQuery = @import("../ECS/ECSManager.zig").GroupQuery;
const EntityComponents = @import("../ECSComponents/EComponents.zig");
const EntitySceneComponent = EntityComponents.EntitySceneComponent;
const TransformComponent = EntityComponents.TransformComponent;
const ViewpointComponent = EntityComponents.ViewpointComponent;
const EntityChildComponent = @import("../ECS/Components.zig").ChildComponent(Entity.Type);
const Vec3 = @import("../Math/MathTypes.zig").Vec3;

const TmplEditPanel = @This();

/// Where the preview camera sits: the same spot as the editor's own camera, looking at the origin where every template's
/// root is (Make Template resets it there)
const CAMERA_POSITION: Vec3(f32) = .{ .x = 0.0, .y = 0.0, .z = 15.0 };

/// The template being edited, with a reference of its own
mTmpl: AssetHandle,
/// The template's root, loaded from its file into EngineContext.mTmplEditWorld
mRoot: SelectedObject,
/// What the component list shows, separate from the editor's own selection
mSelected: ?SelectedObject,
/// Cleared by the window's X, after which the editor closes it (see Close)
mIsOpen: bool = true,

/// An entity template's own scene in the template editing world, so its preview draws only it. A scene template is
/// its own scene, and player and game context templates have nothing to draw
mEntityScene: ?Scene = null,
/// The fixed preview camera, an entity in the editor world. Null for templates with no preview
mCamera: ?Entity = null,
mPreviewTexture: ComputeOutput = .empty,
/// What the preview drew, kept apart from the worlds' own stats
mPreviewStats: RenderStats = .{},
/// The preview area's size as of the last frame it was drawn, which is what the next render is sized to
mPreviewWidth: usize = 0,
mPreviewHeight: usize = 0,
/// Whether the preview area was drawn this frame. A window that is collapsed, or a tab behind another, renders nothing
mIsPreviewShown: bool = false,

/// Loads the template's file into the template editing world, with the root selected. Entity and scene templates get a
/// preview camera in camera_scene, a scene in the editor world. Takes over the caller's reference on tmpl
pub fn Open(engine_context: *EngineContext, tmpl: AssetHandle, camera_scene: Scene) !TmplEditPanel {
    const rel_path = tmpl.GetFileMetaData().mRelPath.items;
    const kind = Serializer.ObjectKindOf(std.fs.path.extension(rel_path)) orelse return error.NotATmplFile;

    var panel: TmplEditPanel = .{ .mTmpl = tmpl, .mRoot = undefined, .mSelected = null };
    switch (kind) {
        .Entity => {
            const entity_scene = try engine_context.mTmplEditWorld.NewScene(engine_context, .GameLayer, Scene.BlankConfig);
            errdefer entity_scene.Delete(engine_context) catch {};
            panel.mRoot = .{ .entity = try Load(Entity, engine_context, tmpl, entity_scene) };
            panel.mEntityScene = entity_scene;
        },
        .Scene => panel.mRoot = .{ .scene_layer = try Load(Scene, engine_context, tmpl, null) },
        .Player => panel.mRoot = .{ .player = try Load(Player, engine_context, tmpl, null) },
        .GameContext => panel.mRoot = .{ .gamecontext = try Load(GameContext, engine_context, tmpl, null) },
    }
    errdefer panel.DeleteObjects(engine_context);

    if (panel.PreviewScene() != null) {
        const camera = try camera_scene.CreateEntity(engine_context, Entity.DefaultConfig);
        panel.mCamera = camera;
        try camera.SetTranslation(engine_context, CAMERA_POSITION);
        _ = try camera.AddComponent(engine_context, ViewpointComponent{});
    }

    panel.mSelected = panel.mRoot;
    return panel;
}

/// Writes the template back to its file. The asset manager then notices the file changed and reloads its copy, so the
/// next Spawn uses the edited template
pub fn Save(self: TmplEditPanel, engine_context: *EngineContext) !void {
    const abs_path = try AbsPath(engine_context, self.mTmpl);
    switch (self.mRoot) {
        inline else => |root| try TextSerializer.SerializeECSObject(engine_context, root, abs_path),
    }
}

/// Saves, then takes the template and its preview camera away (at the end of the frame), frees the preview and lets go
/// of the handle. If the save fails nothing else happens, so the edits are still there to try again
pub fn Close(self: *TmplEditPanel, engine_context: *EngineContext) !void {
    try self.Save(engine_context);
    self.DeleteObjects(engine_context);
    //only a preview that was drawn has a texture, and freeing one needs the GPU device
    if (self.mPreviewTexture.IsCreated()) self.mPreviewTexture.Deinit(engine_context);
    self.mTmpl.ReleaseAsset();
}

pub fn IsTmpl(self: TmplEditPanel, tmpl: AssetHandle) bool {
    return self.mTmpl.mID == tmpl.mID;
}

/// The file name to show, and the template's path after ### so each template file gets its own window, whose size and
/// dock slot imgui remembers between runs. The asset id would not do for that, it depends on the order things load in
pub fn WindowName(self: TmplEditPanel, engine_context: *EngineContext) ![:0]const u8 {
    const rel_path = self.mTmpl.GetFileMetaData().mRelPath.items;
    return try std.fmt.allocPrintSentinel(engine_context.FrameAllocator(), "Template - {s}###Tmpl_{s}", .{ std.fs.path.basename(rel_path), rel_path }, 0);
}

pub fn OnImguiRender(self: *TmplEditPanel, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("TmplEditPanel::OnImguiRender", @src());
    defer zone.Deinit();

    self.mIsPreviewShown = false;

    const window_name = try self.WindowName(engine_context);
    //room for all three panes the first time a template is opened. Left to itself imgui sizes a new window to its
    //contents, and the panes are sized from the window, so it would open tiny
    imgui.igSetNextWindowSize(.{ .x = 1000, .y = 500 }, imgui.ImGuiCond_FirstUseEver);
    const is_visible = imgui.igBegin(window_name.ptr, &self.mIsOpen, 0);
    defer imgui.igEnd();
    if (!is_visible) return;

    if (imgui.igButton("Save", .{ .x = 0, .y = 0 })) {
        try self.Save(engine_context);
    }

    //a delete from the tree below only goes through at the end of the frame, so the selection is gone by the next one
    if (self.mSelected) |selected| {
        const is_active = switch (selected) {
            inline else => |object| object.IsActive(),
        };
        if (!is_active) self.mSelected = null;
    }

    const has_preview = self.mCamera != null;
    const available = imgui.igGetContentRegionAvail();

    if (imgui.igBeginChild_Str("Hierarchy", .{ .x = available.x * if (has_preview) @as(f32, 0.25) else 0.4, .y = 0 }, imgui.ImGuiChildFlags_Borders | imgui.ImGuiChildFlags_ResizeX, 0)) {
        switch (self.mRoot) {
            inline else => |root| try self.RenderTree(engine_context, root),
        }
    }
    imgui.igEndChild();

    if (has_preview) {
        imgui.igSameLine(0.0, -1.0);
        if (imgui.igBeginChild_Str("Preview", .{ .x = available.x * 0.45, .y = 0 }, imgui.ImGuiChildFlags_Borders | imgui.ImGuiChildFlags_ResizeX, 0)) {
            self.RenderPreviewImage();
        }
        imgui.igEndChild();
    }

    imgui.igSameLine(0.0, -1.0);

    if (imgui.igBeginChild_Str("Components", .{ .x = 0, .y = 0 }, imgui.ImGuiChildFlags_Borders, 0)) {
        if (self.mSelected) |selected| {
            switch (selected) {
                inline else => |object| try ComponentsPanel.RenderComponents(@TypeOf(object), engine_context, object),
            }
        }
    }
    imgui.igEndChild();
}

/// Draws the template into the preview texture, sized to the preview area as of when the window was last drawn. Has
/// to run inside the renderer's frame, after OnImguiRender, the same as the editor's viewports
pub fn RenderPreview(self: *TmplEditPanel, engine_context: *EngineContext) !void {
    const camera = self.mCamera orelse return;
    const scene = self.PreviewScene() orelse return;
    //nothing to render for a preview that isn't on screen, or that has no room yet
    if (!self.mIsPreviewShown or self.mPreviewWidth < 1 or self.mPreviewHeight < 1) return;

    const transform_component = camera.GetComponent(TransformComponent).?;
    const viewpoint_component = camera.GetComponent(ViewpointComponent).?;

    //the viewpoint has to match the texture it renders into, the ray math and the shader's bounds check read its size
    viewpoint_component.SetViewportSize(self.mPreviewWidth, self.mPreviewHeight);
    try self.mPreviewTexture.Resize(engine_context, self.mPreviewWidth, self.mPreviewHeight);
    if (!self.mPreviewTexture.IsCreated()) return;

    //the renderer adds to stats, and these are only ever this frame's preview
    self.mPreviewStats.ResetStats();
    try engine_context.mRenderer.RenderScene(
        scene,
        &self.mPreviewStats,
        engine_context,
        Renderer.BuildPushConstants(transform_component, viewpoint_component),
        Renderer.CameraView.FromViewpoint(transform_component, viewpoint_component, engine_context.mAppWindow.GetDisplayScale()),
        &self.mPreviewTexture,
        .OverlayGame,
    );
}

/// The scene the preview draws: an entity template's own scene, or a scene template itself. Null for players and
/// game contexts, which have nothing to draw
fn PreviewScene(self: TmplEditPanel) ?Scene {
    if (self.mEntityScene) |entity_scene| return entity_scene;
    return switch (self.mRoot) {
        .scene_layer => |scene| scene,
        else => null,
    };
}

/// Puts last frame's preview in the preview area and remembers the area's size for the next render
fn RenderPreviewImage(self: *TmplEditPanel) void {
    const size = imgui.igGetContentRegionAvail();
    self.mPreviewWidth = @intFromFloat(@max(size.x, 0.0));
    self.mPreviewHeight = @intFromFloat(@max(size.y, 0.0));
    self.mIsPreviewShown = true;

    //the first frame has nothing rendered yet
    if (!self.mPreviewTexture.IsCreated()) return;

    const top_left = imgui.igGetCursorScreenPos();
    const tex_ref = imgui.ImTextureRef_c{
        ._TexData = null,
        ._TexID = @as(imgui.ImTextureID, @intFromPtr(self.mPreviewTexture.GetTexture())),
    };
    imgui.ImDrawList_AddImage(
        imgui.igGetWindowDrawList(),
        tex_ref,
        top_left,
        .{ .x = top_left.x + size.x, .y = top_left.y + size.y },
        .{ .x = 0, .y = 0 },
        .{ .x = 1, .y = 1 },
        0xFFFFFFFF,
    );
}

/// The root and everything under it, then for a scene its entities
fn RenderTree(self: *TmplEditPanel, engine_context: *EngineContext, root: anytype) !void {
    try ECSDisplay.RenderObject(@TypeOf(root), engine_context, root, .{ .mSelection = &self.mSelected, .mIsRoot = true });

    if (@TypeOf(root) == Scene) {
        imgui.igSeparatorText("Entities");
        //only the top level ones, each draws its own children
        const EntitySceneQuery = GroupQuery{ .Component = EntitySceneComponent };
        const EntityChildQuery = GroupQuery{ .Component = EntityChildComponent };
        const root_entities = try root.GetEntityGroup(engine_context.FrameAllocator(), .{
            .Not = .{
                .mFirst = &EntitySceneQuery,
                .mSecond = &EntityChildQuery,
            },
        });
        for (root_entities.items) |entity_id| {
            try ECSDisplay.RenderObject(Entity, engine_context, root.GetEntity(entity_id), .{ .mSelection = &self.mSelected });
        }
    }
}

/// Deletes (at the end of the frame) the template and the preview camera. An entity template goes with its own scene
fn DeleteObjects(self: TmplEditPanel, engine_context: *EngineContext) void {
    const result = if (self.mEntityScene) |entity_scene|
        entity_scene.Delete(engine_context)
    else switch (self.mRoot) {
        inline else => |root| root.Delete(engine_context),
    };
    result catch |err| std.log.err("Failed to delete a closed template: {s}", .{@errorName(err)});

    if (self.mCamera) |camera| {
        camera.Delete(engine_context) catch |err| std.log.err("Failed to delete a template's preview camera: {s}", .{@errorName(err)});
    }
}

/// A blank object in the template editing world, filled from the template's file. An entity goes in entity_scene
fn Load(comptime obj_t: type, engine_context: *EngineContext, tmpl: AssetHandle, entity_scene: ?Scene) !obj_t {
    const object = if (obj_t == Entity)
        try entity_scene.?.CreateEntity(engine_context, Entity.BlankConfig)
    else
        try engine_context.mTmplEditWorld.CreateBlank(obj_t, engine_context);
    errdefer object.Delete(engine_context) catch {};

    //TextSerializer rather than Serializer.DeserializeECSObj: the panel saves to the template's own path, so there is
    //no use recording the file against the object's UUID in mFileObjects
    try TextSerializer.DeserializeECSObj(engine_context, object, try AbsPath(engine_context, tmpl));
    engine_context.mSerializer.ResolveUUIDs();
    return object;
}

fn AbsPath(engine_context: *EngineContext, tmpl: AssetHandle) ![]const u8 {
    const file_data = tmpl.GetFileMetaData();
    return try engine_context.mAssetManager.GetAbsPath(engine_context.FrameAllocator(), file_data.mRelPath.items, file_data.mPathType);
}

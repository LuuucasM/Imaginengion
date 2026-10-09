//! A window for editing one template, in the editor's own UI: a Save button, then the template's tree, a preview of it
//! and the selected object's components side by side, with dividers to drag. Closing the window saves it and takes it
//! away. The template is loaded from its file into its own scene in EngineContext.mTmplEditWorld, where nothing runs,
//! and written back to the same file. The selection is the window's own, not the editor's. A scene template's tree is
//! the scene, then its entities; players and game modes have no preview. The editor keeps one per open template
const std = @import("std");
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const AssetHandle = @import("../ECSObjects/AssetHandle.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const Scene = @import("../ECSObjects/Scene.zig");
const Player = @import("../ECSObjects/Player.zig");
const GameContext = @import("../ECSObjects/GameContext.zig");
const SelectedObject = @import("../Programs/EditorProgram.zig").SelectedObject;
const Serializer = @import("../Serializer/Serializer.zig");
const TextSerializer = @import("../Serializer/TextSerializer.zig");
const Renderer = @import("../Renderer/Renderer.zig");
const GroupQuery = @import("../ECS/ECSManager.zig").GroupQuery;
const Widgets = @import("../UI/Widgets.zig");
const WidgetActions = @import("../UI/WidgetActions.zig");
const UIEvent = @import("../Events/UIEventData.zig").EventT;
const PointerDroppedEvent = @import("../Events/PointerEventData.zig").PointerDroppedEvent;
const HierarchyPanel = @import("HierarchyPanel.zig").HierarchyPanel;
const ComponentsPanel = @import("ComponentsPanel.zig");
const TmplPreview = @import("TmplPreview.zig");
const EntityComponents = @import("../ECSComponents/EComponents.zig");
const EntitySceneComponent = EntityComponents.EntitySceneComponent;
const LayoutItemComponent = EntityComponents.LayoutItemComponent;
const EntityChildComponent = @import("../ECS/Components.zig").ChildComponent(Entity.Type);
const MathTypes = @import("../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;

const TmplEditPanel = @This();

/// How big the window is, where it opens (from the middle of the editor UI), how wide the tree and the preview start,
/// and how much of the window's height the title, the Save row and the padding take
const SIZE = Vec2(f32){ .x = 960, .y = 540 };
const AT = Vec2(f32){ .x = 0, .y = 0 };
const TREE_WIDTH: f32 = 240;
const PREVIEW_WIDTH: f32 = 360;
const ABOVE_PANES: f32 = 80;

/// The tree, for the kind of object the template is. A scene's is the scene, then its entities
const Trees = union(enum) {
    entity: HierarchyPanel(Entity),
    scene_layer: struct { Scene: HierarchyPanel(Scene), Entities: HierarchyPanel(Entity) },
    player: HierarchyPanel(Player),
    gamecontext: HierarchyPanel(GameContext),
};

/// The template being edited, with a reference of its own
mTmpl: AssetHandle,
/// The template's root, loaded from its file into EngineContext.mTmplEditWorld
mRoot: SelectedObject,
/// What the components pane shows, apart from the editor's own selection
mSelected: ?SelectedObject = null,
/// An entity template's own scene in the template editing world, so its preview draws only it
mEntityScene: ?Scene = null,
mWindow: Entity = .uninit,
mSave: Entity = .uninit,
mTrees: Trees = undefined,
mComponents: ComponentsPanel = .{},
/// Null for templates with nothing to draw
mPreview: ?TmplPreview = null,

/// Loads the template's file into the template editing world with its root selected, and builds its window at the top
/// of `ui_scene`. Entity and scene templates get a preview, its camera in `camera_scene` (a game layer scene in the
/// editor world). Takes over the caller's reference on tmpl
pub fn Open(engine_context: *EngineContext, tmpl: AssetHandle, camera_scene: Scene, ui_scene: Scene, options: Widgets.Options) !TmplEditPanel {
    const zone = Tracy.ZoneInit("TmplEditPanel::Open", @src());
    defer zone.Deinit();
    const rel_path = tmpl.GetFileMetaData().mRelPath.items;
    const kind = Serializer.ObjectKindOf(std.fs.path.extension(rel_path)) orelse return error.NotATmplFile;

    var self: TmplEditPanel = .{ .mTmpl = tmpl, .mRoot = undefined };
    switch (kind) {
        .Entity => {
            const entity_scene = try engine_context.mTmplEditWorld.NewScene(engine_context, .GameLayer, Scene.BlankConfig);
            errdefer entity_scene.Delete(engine_context) catch {};
            self.mRoot = .{ .entity = try Load(Entity, engine_context, tmpl, entity_scene) };
            self.mEntityScene = entity_scene;
        },
        .Scene => self.mRoot = .{ .scene_layer = try Load(Scene, engine_context, tmpl, null) },
        .Player => self.mRoot = .{ .player = try Load(Player, engine_context, tmpl, null) },
        .GameContext => self.mRoot = .{ .gamecontext = try Load(GameContext, engine_context, tmpl, null) },
    }
    errdefer self.DeleteObjects(engine_context);
    self.mSelected = self.mRoot;
    try self.BuildWindow(engine_context, camera_scene, ui_scene, options);
    return self;
}

/// The window: the Save row, then tree | preview | components, or tree | components with no preview
fn BuildWindow(self: *TmplEditPanel, engine_context: *EngineContext, camera_scene: Scene, ui_scene: Scene, options: Widgets.Options) !void {
    const title = try std.fmt.allocPrint(engine_context.FrameAllocator(), "Template - {s}", .{std.fs.path.basename(self.mTmpl.GetFileMetaData().mRelPath.items)});
    const window = try Widgets.FloatingWindow(engine_context, ui_scene, title, SIZE, AT, options);
    self.mWindow = window.Window;
    const toolbar = try Widgets.Row(engine_context, .{ .Entity = window.Content });
    self.mSave = try Widgets.Button(engine_context, .{ .Entity = toolbar }, "Save");

    //the window's content scrolls, so the panes get a height of their own rather than filling it
    const split = try Widgets.Split(engine_context, .{ .Entity = window.Content }, .Row, .First, TREE_WIDTH, options);
    split.Root.GetComponent(LayoutItemComponent).?.mHeight = .{ .Fixed = SIZE.y - ABOVE_PANES };
    const tree_pane = split.First;

    const components_pane = if (self.PreviewScene() != null) blk: {
        const right = try Widgets.Split(engine_context, .{ .Entity = split.Second }, .Row, .First, PREVIEW_WIDTH, options);
        self.mPreview = try TmplPreview.Build(engine_context, camera_scene, right.First);
        break :blk right.Second;
    } else split.Second;
    self.mComponents = try ComponentsPanel.Build(engine_context, components_pane, options);

    self.mTrees = switch (self.mRoot) {
        .entity => .{ .entity = try HierarchyPanel(Entity).BuildForRoots(engine_context, tree_pane, options) },
        .scene_layer => blk: {
            const scene_tree = try HierarchyPanel(Scene).BuildForRoots(engine_context, tree_pane, options);
            _ = try Widgets.Label(engine_context, .{ .Entity = tree_pane }, "Entities");
            break :blk .{ .scene_layer = .{ .Scene = scene_tree, .Entities = try HierarchyPanel(Entity).BuildForRoots(engine_context, tree_pane, options) } };
        },
        .player => .{ .player = try HierarchyPanel(Player).BuildForRoots(engine_context, tree_pane, options) },
        .gamecontext => .{ .gamecontext = try HierarchyPanel(GameContext).BuildForRoots(engine_context, tree_pane, options) },
    };
}

pub fn Deinit(self: *TmplEditPanel, engine_allocator: std.mem.Allocator) void {
    switch (self.mTrees) {
        .scene_layer => |*trees| {
            trees.Scene.Deinit(engine_allocator);
            trees.Entities.Deinit(engine_allocator);
        },
        inline else => |*tree| tree.Deinit(engine_allocator),
    }
    self.mComponents.Deinit(engine_allocator);
}

/// Whether its window is open. Closed, the editor saves it and takes it away (Close)
pub fn IsOpen(self: TmplEditPanel) bool {
    return WidgetActions.IsWindowOpen(self.mWindow);
}

/// The window opened again in front of the others: the template opened while it already was, or a save that failed
pub fn BringForward(self: TmplEditPanel, engine_context: *EngineContext) !void {
    try WidgetActions.OpenWindow(engine_context, self.mWindow);
}

pub fn IsTmpl(self: TmplEditPanel, tmpl: AssetHandle) bool {
    return self.mTmpl.mID == tmpl.mID;
}

/// Once a frame, before layout, while it is open: the trees and the components pane, for the window's own selection
pub fn Update(self: *TmplEditPanel, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("TmplEditPanel::Update", @src());
    defer zone.Deinit();
    if (!self.IsOpen()) return;
    //a delete from the tree only goes through at the end of the frame, so the selection is gone by the next one
    if (self.mSelected) |selected| {
        const is_active = switch (selected) {
            inline else => |object| object.IsActive(),
        };
        if (!is_active) self.mSelected = null;
    }

    switch (self.mTrees) {
        .entity => |*tree| try tree.UpdateRoots(engine_context, &.{self.mRoot.entity}, self.mSelected),
        .scene_layer => |*trees| {
            const scene = self.mRoot.scene_layer;
            try trees.Scene.UpdateRoots(engine_context, &.{scene}, self.mSelected);
            //only the top level ones, each with its own children under it
            const EntitySceneQuery = GroupQuery{ .Component = EntitySceneComponent };
            const EntityChildQuery = GroupQuery{ .Component = EntityChildComponent };
            const ids = try scene.GetEntityGroup(engine_context.FrameAllocator(), .{ .Not = .{ .mFirst = &EntitySceneQuery, .mSecond = &EntityChildQuery } });
            const entities = try engine_context.FrameAllocator().alloc(Entity, ids.items.len);
            for (ids.items, entities) |id, *entity| entity.* = scene.GetEntity(id);
            try trees.Entities.UpdateRoots(engine_context, entities, self.mSelected);
        },
        .player => |*tree| try tree.UpdateRoots(engine_context, &.{self.mRoot.player}, self.mSelected),
        .gamecontext => |*tree| try tree.UpdateRoots(engine_context, &.{self.mRoot.gamecontext}, self.mSelected),
    }
    try self.mComponents.Update(engine_context, self.mSelected);
}

/// Draws its preview, sized to its pane as `ui_view` (the editor UI's camera) sees it. Inside the renderer's frame,
/// before the editor UI is drawn
pub fn RenderPreview(self: *TmplEditPanel, engine_context: *EngineContext, ui_view: Renderer.CameraView) !void {
    if (!self.IsOpen()) return;
    if (self.mPreview) |*preview| try preview.Render(engine_context, self.PreviewScene().?, ui_view);
}

/// A left click on `entity`: Save, a tree row or menu item, or something in the components pane. EditUIElement there
/// does nothing: the UI Element panel shows the editor's selection, not the window's
pub fn OnLeftClick(self: *TmplEditPanel, engine_context: *EngineContext, entity: Entity) !void {
    if (entity.mID == self.mSave.mID and entity.mManager == self.mSave.mManager) return try self.Save(engine_context);
    const world = &engine_context.mTmplEditWorld;
    switch (self.mTrees) {
        .scene_layer => |*trees| {
            if (trees.Scene.ActionOf(entity)) |action| try trees.Scene.Run(engine_context, action, world, &self.mSelected);
            if (trees.Entities.ActionOf(entity)) |action| try trees.Entities.Run(engine_context, action, world, &self.mSelected);
        },
        inline else => |*tree| if (tree.ActionOf(entity)) |action| try tree.Run(engine_context, action, world, &self.mSelected),
    }
    if (self.mComponents.ActionOf(entity)) |action| {
        if (action != .EditUIElement) try self.mComponents.Run(engine_context, action);
    }
}

/// A right click on `entity`: a tree row's menu opening
pub fn OnRightClick(self: *TmplEditPanel, engine_context: *EngineContext, entity: Entity) !void {
    switch (self.mTrees) {
        .scene_layer => |*trees| {
            try trees.Scene.OnRightClick(engine_context, entity);
            try trees.Entities.OnRightClick(engine_context, entity);
        },
        inline else => |*tree| try tree.OnRightClick(engine_context, entity),
    }
}

pub fn OnUIEvent(self: *const TmplEditPanel, engine_context: *EngineContext, event: UIEvent) !void {
    try self.mComponents.OnUIEvent(engine_context, event);
}

pub fn OnDrop(self: *const TmplEditPanel, dropped: PointerDroppedEvent) void {
    self.mComponents.OnDrop(dropped);
}

/// Writes the template back to its file. The asset manager then notices the file changed and reloads its copy, so the
/// next Spawn uses the edited template
pub fn Save(self: TmplEditPanel, engine_context: *EngineContext) !void {
    const abs_path = try AbsPath(engine_context, self.mTmpl);
    switch (self.mRoot) {
        inline else => |root| try TextSerializer.SerializeECSObject(engine_context, root, abs_path),
    }
}

/// Saves, then takes the template, its preview and its window away (at the end of the frame) and lets go of the
/// handle. If the save fails nothing else happens, so the edits are still there to try again
pub fn Close(self: *TmplEditPanel, engine_context: *EngineContext) !void {
    try self.Save(engine_context);
    self.DeleteObjects(engine_context);
    if (self.mPreview) |preview| try preview.Delete(engine_context);
    //everything in the window, and the menus and lists it opens, which live at the top of the scene
    try Widgets.Remove(engine_context, self.mWindow, &.{});
    self.Deinit(engine_context.EngineAllocator());
    self.mTmpl.ReleaseAsset();
}

/// The scene the preview draws: an entity template's own scene, or a scene template itself. Null for players and game
/// contexts, which have nothing to draw
fn PreviewScene(self: TmplEditPanel) ?Scene {
    if (self.mEntityScene) |entity_scene| return entity_scene;
    return switch (self.mRoot) {
        .scene_layer => |scene| scene,
        else => null,
    };
}

/// Deletes (at the end of the frame) the template. An entity template goes with its own scene
fn DeleteObjects(self: TmplEditPanel, engine_context: *EngineContext) void {
    const result = if (self.mEntityScene) |entity_scene|
        entity_scene.Delete(engine_context)
    else switch (self.mRoot) {
        inline else => |root| root.Delete(engine_context),
    };
    result catch |err| std.log.err("Failed to delete a closed template: {s}", .{@errorName(err)});
}

/// A blank object in the template editing world, filled from the template's file. An entity goes in entity_scene
fn Load(comptime obj_t: type, engine_context: *EngineContext, tmpl: AssetHandle, entity_scene: ?Scene) !obj_t {
    const object = if (obj_t == Entity)
        try entity_scene.?.CreateEntity(engine_context, Entity.BlankConfig)
    else
        try engine_context.mTmplEditWorld.CreateBlank(obj_t, engine_context);
    errdefer object.Delete(engine_context) catch {};

    //TextSerializer rather than Serializer.DeserializeECSObj: the window saves to the template's own path, so there is
    //no use recording the file against the object's UUID in mFileObjects
    try TextSerializer.DeserializeECSObj(engine_context, object, try AbsPath(engine_context, tmpl));
    engine_context.mSerializer.ResolveUUIDs();
    return object;
}

fn AbsPath(engine_context: *EngineContext, tmpl: AssetHandle) ![]const u8 {
    const file_data = tmpl.GetFileMetaData();
    return try engine_context.mAssetManager.GetAbsPath(engine_context.FrameAllocator(), file_data.mRelPath.items, file_data.mPathType);
}

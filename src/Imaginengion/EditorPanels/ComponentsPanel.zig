//! The Components panel, in the editor's own UI, in the shell's Components tab: the selected object's name, then its
//! components (ComponentList: a folding header each with its UIRender's rows, right click a header to delete it or the
//! panel to add one). Under some components it adds rows that need the object rather than only the component (After):
//! a rigid body's type, a scene's layer, an audio component's Preview and Stop, a template reference's Edit Template,
//! a UI element's components with Edit UI Element, and a player's possessed entity, which an entity's row dropped on
//! possesses (Player.Possess, which links both sides) and Clear lets go of. A line says why when there is nothing to list. Every frame the
//! selection and which components it has are checked against what was built, and it is built again when they differ
const std = @import("std");
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const Scene = @import("../ECSObjects/Scene.zig");
const Player = @import("../ECSObjects/Player.zig");
const GameContext = @import("../ECSObjects/GameContext.zig");
const UIManager = @import("../UI/UIManager.zig");
const Widgets = @import("../UI/Widgets.zig");
const WidgetActions = @import("../UI/WidgetActions.zig");
const Inspector = @import("../UI/Inspector.zig");
const EntityUIEvent = @import("../Events/UIEventData.zig").EntityEvent;
const PointerDroppedEvent = @import("../Events/PointerEventData.zig").PointerDroppedEvent;
const SelectedObject = @import("../Programs/EditorProgram.zig").SelectedObject;
const ComponentList = @import("ComponentList.zig").ComponentList;

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const LayoutItemComponent = EntityComponents.LayoutItemComponent;
const SurfaceComponent = EntityComponents.SurfaceComponent;
const RigidBodyComponent = EntityComponents.RigidBodyComponent;
const AudioComponent = EntityComponents.AudioComponent;
const UIElementComponent = EntityComponents.UIElementComponent;
const TmplRefComponent = EntityComponents.TmplRefComponent;
const PlayerSlotComponent = EntityComponents.PlayerSlotComponent;
const ObjectRefComponent = EntityComponents.ObjectRefComponent;
const PossessComponent = @import("../ECSComponents/PComponents.zig").PossessComponent;
const SceneComponent = @import("../ECSComponents/SComponents.zig").SceneComponent;
const UIComponents = @import("../ECSComponents/UIComponents.zig");

const ComponentsPanel = @This();

const EntityList = ComponentList(Entity, &EntityComponents.ComponentPanelList);
const SceneList = ComponentList(Scene, &@import("../ECSComponents/SComponents.zig").ComponentsPanelList);
const PlayerList = ComponentList(Player, &@import("../ECSComponents/PComponents.zig").ComponentsPanelList);
const GameContextList = ComponentList(GameContext, &@import("../ECSComponents/GCComponents.zig").ComponentsPanelList);

/// What a click on the panel does
pub const Action = union(enum) {
    /// a component added or deleted, by its place in the selected object's list (ComponentList)
    Add: usize,
    Delete: usize,
    /// an audio component's
    Preview,
    Stop,
    /// the template the selected object was made from, opened for editing
    EditTemplate,
    /// the UI Element panel shown
    EditUIElement,
    /// the selected player lets go of the entity it possesses
    Unpossess,
};

const ButtonAction = struct {
    Button: Entity,
    Action: Action,
};

/// The panel's content, in the Components tab
mArea: Entity = .uninit,
/// The selected object's name, folded away when nothing is selected
mTitle: Entity = .uninit,
/// Why there is nothing to list, folded away when there is
mMessage: Entity = .uninit,
mEntityList: EntityList = .{},
mSceneList: SceneList = .{},
mPlayerList: PlayerList = .{},
mGameContextList: GameContextList = .{},
/// The object the components were built for, and which of its list's components it had then
mBuiltFor: ?SelectedObject = null,
mBuiltPresent: u64 = 0,
/// The buttons it added under components, and the rigid body type dropdown, if there is one
mButtons: std.ArrayList(ButtonAction) = .empty,
mBodyType: ?Entity = null,
/// The selected player's possessed entity's box, which an entity's row can be dropped on
mPossessBox: ?Entity = null,
mOptions: Widgets.Options = .{},

/// Builds the panel into `page`, the shell's Components tab
pub fn Build(engine_context: *EngineContext, page: Entity, options: Widgets.Options) !ComponentsPanel {
    const zone = Tracy.ZoneInit("ComponentsPanel::Build", @src());
    defer zone.Deinit();
    const area = try Widgets.ScrollArea(engine_context, .{ .Entity = page });
    //a background, so a right click on the empty part of the panel opens the Add menu
    _ = try area.AddComponent(engine_context, SurfaceComponent{});
    try UIManager.Style(engine_context, area, "Window");
    return .{
        .mArea = area,
        .mTitle = try Widgets.Label(engine_context, .{ .Entity = area }, ""),
        .mMessage = try Widgets.Label(engine_context, .{ .Entity = area }, ""),
        .mOptions = options,
    };
}

pub fn Deinit(self: *ComponentsPanel, engine_allocator: std.mem.Allocator) void {
    self.mEntityList.Deinit(engine_allocator);
    self.mSceneList.Deinit(engine_allocator);
    self.mPlayerList.Deinit(engine_allocator);
    self.mGameContextList.Deinit(engine_allocator);
    self.mButtons.deinit(engine_allocator);
}

/// Whether it is shown in its tab (the Window menu's Components)
pub fn IsOpen(self: ComponentsPanel) bool {
    return !self.mArea.GetComponent(LayoutItemComponent).?.mCollapsed;
}

pub fn Toggle(self: ComponentsPanel, engine_context: *EngineContext) !void {
    const item = self.mArea.GetComponent(LayoutItemComponent).?;
    item.mCollapsed = !item.mCollapsed;
    try self.mArea.MarkLayoutDirty(engine_context);
}

/// Once a frame, before layout, while it is shown: the components built again if the selection or which components
/// it has changed, or a field asked for it, and the lines above them
pub fn Update(self: *ComponentsPanel, engine_context: *EngineContext, selected: ?SelectedObject) !void {
    const zone = Tracy.ZoneInit("ComponentsPanel::Update", @src());
    defer zone.Deinit();
    if (!self.IsOpen()) return;

    const object = selected orelse {
        try self.Clear(engine_context);
        try ShowLine(engine_context, self.mTitle, "");
        return try ShowLine(engine_context, self.mMessage, "Select an object to see its components");
    };
    if (!IsActive(object)) {
        try self.Clear(engine_context);
        try ShowLine(engine_context, self.mTitle, "");
        return try ShowLine(engine_context, self.mMessage, "");
    }

    const present = PresentOf(object);
    const stale = if (self.mBuiltFor) |built| !SameObject(built, object) or present != self.mBuiltPresent or self.TakeRebuild(engine_context) else true;
    if (stale) try self.Rebuild(engine_context, object, present);
    try ShowLine(engine_context, self.mTitle, NameOf(object));
    try ShowLine(engine_context, self.mMessage, if (present == 0) "No components yet. Right click to add one" else "");
}

/// What a click on `entity` does: one of its buttons, or a component menu's Add or Delete. Null for anything else
pub fn ActionOf(self: *const ComponentsPanel, entity: Entity) ?Action {
    for (self.mButtons.items) |entry| {
        if (Same(entry.Button, entity)) return entry.Action;
    }
    const built = self.mBuiltFor orelse return null;
    return switch (built) {
        .entity => ListAction(self.mEntityList.ActionOf(entity)),
        .scene_layer => ListAction(self.mSceneList.ActionOf(entity)),
        .player => ListAction(self.mPlayerList.ActionOf(entity)),
        .gamecontext => ListAction(self.mGameContextList.ActionOf(entity)),
    };
}

/// Does what a click asked for, other than EditUIElement, which is the editor's (it shows the UI Element panel). The
/// components are built again the next frame if they changed
pub fn Run(self: *const ComponentsPanel, engine_context: *EngineContext, action: Action) !void {
    const built = self.mBuiltFor orelse return;
    switch (action) {
        .Add, .Delete => {
            switch (built) {
                .entity => try self.mEntityList.Run(engine_context, ToListAction(EntityList, action)),
                .scene_layer => try self.mSceneList.Run(engine_context, ToListAction(SceneList, action)),
                .player => try self.mPlayerList.Run(engine_context, ToListAction(PlayerList, action)),
                .gamecontext => try self.mGameContextList.Run(engine_context, ToListAction(GameContextList, action)),
            }
        },
        .Preview => if (built == .entity) {
            _ = try built.entity.PlayAudio(engine_context);
        },
        .Stop => if (built == .entity) built.entity.StopAudio(),
        .EditTemplate => {
            const tmpl_ref = switch (built) {
                inline else => |object| object.GetComponent(TmplRefComponent),
            } orelse return;
            if (!tmpl_ref.mTmpl.IsIDValid()) return;
            //the event carries a reference of its own, which the editor takes over
            tmpl_ref.mTmpl.RetainAsset();
            try engine_context.mEditorEventManager.Insert(engine_context.EngineAllocator(), .EndOfFrame, .{ .OpenTmplEvent = .{ .mTmpl = tmpl_ref.mTmpl } });
        },
        .EditUIElement => {},
        .Unpossess => if (built == .player) {
            const possess = built.player.GetComponent(PossessComponent) orelse return;
            //both sides: the entity's slot stops naming the player, if it still does
            const possessed = possess.mPossessedEntity;
            if (possessed.mID != Entity.NullObject and possessed.IsActive()) {
                if (possessed.GetComponent(PlayerSlotComponent)) |slot| {
                    if (slot.mPlayerEntity.mID == built.player.mID) slot.mPlayerEntity = .uninit;
                }
            }
            possess.mPossessedEntity = .uninit;
        },
    }
}

/// A drop on the panel: an entity's row on the selected player's possessed entity, which it possesses
pub fn OnDrop(self: *const ComponentsPanel, on: Entity, dropped: PointerDroppedEvent) void {
    const box = self.mPossessBox orelse return;
    if (!Same(on, box)) return;
    const built = self.mBuiltFor orelse return;
    if (built != .player) return;
    const object_ref = dropped.mSource.GetComponent(ObjectRefComponent) orelse return;
    if (object_ref.mObject != .entity) {
        std.log.warn("A player can only possess an entity", .{});
        return;
    }
    if (!object_ref.mObject.entity.IsActive()) return;
    built.player.Possess(object_ref.mObject.entity);
}

/// One of the frame's UI events: a new type picked for the selected entity's rigid body
pub fn OnUIEvent(self: *const ComponentsPanel, engine_context: *EngineContext, event: EntityUIEvent) !void {
    const changed = switch (event.mEvent) {
        .ValueChanged => event.mEntity,
        else => return,
    };
    const dropdown = self.mBodyType orelse return;
    if (!Same(changed, dropdown)) return;
    const built = self.mBuiltFor orelse return;
    if (built != .entity) return;
    const index = WidgetActions.ChosenIndex(dropdown) orelse return;
    inline for (Entity.BodyTypeTags, 0..) |tag_type, i| {
        if (i == index) try built.entity.SetBodyType(engine_context, tag_type);
    }
}

/// Rows of its own under a component's (see Inspector.RenderComponentWith), for what needs the object
pub fn After(self: *ComponentsPanel, comptime component_type: type, ui: *Inspector.Builder, component: *component_type, object: anytype) !void {
    const engine_allocator = ui.mEngineContext.EngineAllocator();
    const Object = @TypeOf(object);
    if (comptime component_type == RigidBodyComponent and Object == Entity) {
        //which of the body type tags it has, picked like an enum
        var names: [Entity.BodyTypeTags.len][]const u8 = undefined;
        var chosen: ?usize = null;
        inline for (Entity.BodyTypeTags, 0..) |tag_type, i| {
            names[i] = tag_type.Name;
            if (object.HasComponent(tag_type)) chosen = i;
        }
        const row = try Widgets.Row(ui.mEngineContext, .{ .Entity = ui.mParent });
        const label = try Widgets.Label(ui.mEngineContext, .{ .Entity = row }, "Body Type");
        label.GetComponent(LayoutItemComponent).?.mWidth = .{ .Fixed = Inspector.LABEL_WIDTH };
        self.mBodyType = try Widgets.Dropdown(ui.mEngineContext, .{ .Entity = row }, &names, chosen, self.mOptions);
    }
    if (comptime component_type == PossessComponent and Object == Player) {
        //possessing links both sides, so the box takes the drop itself (OnDrop) rather than writing the field
        //the copy the rows are built from, which field offsets are measured from
        const box = try ui.EntityRef(&component.mPossessedEntity, "Possessed", .{ .Writes = false });
        self.mPossessBox = box;
        const menu = try Widgets.ContextMenu(ui.mEngineContext, box, self.mOptions);
        const clear = try Widgets.MenuItem(ui.mEngineContext, menu, "Clear", .{ .StockScripts = self.mOptions.StockScripts });
        try self.mButtons.append(engine_allocator, .{ .Button = clear, .Action = .Unpossess });
    }
    if (comptime component_type == SceneComponent and Object == Scene) {
        //shown, not edited: the scene stack slots a scene by its layer when it is made
        try ui.Note(try std.fmt.allocPrint(ui.mEngineContext.FrameAllocator(), "Layer: {s}", .{@tagName(object.GetLayer())}));
    }
    if (comptime component_type == AudioComponent and Object == Entity) {
        const buttons = try ui.Buttons(&.{ "Preview", "Stop" });
        try self.mButtons.append(engine_allocator, .{ .Button = buttons[0], .Action = .Preview });
        try self.mButtons.append(engine_allocator, .{ .Button = buttons[1], .Action = .Stop });
    }
    if (comptime component_type == TmplRefComponent) {
        if (object.GetComponent(TmplRefComponent).?.mTmpl.IsIDValid()) {
            const buttons = try ui.Buttons(&.{"Edit Template"});
            try self.mButtons.append(engine_allocator, .{ .Button = buttons[0], .Action = .EditTemplate });
        }
    }
    if (comptime component_type == UIElementComponent and Object == Entity) {
        var count: usize = 0;
        if (UIManager.ElementOf(object)) |element| {
            inline for (UIComponents.ComponentsPanelList) |ui_component| {
                if (element.HasComponent(ui_component)) {
                    try ui.Note(ui_component.Name);
                    count += 1;
                }
            }
        }
        if (count == 0) try ui.Note("No UI components yet");
        const buttons = try ui.Buttons(&.{"Edit UI Element"});
        try self.mButtons.append(engine_allocator, .{ .Button = buttons[0], .Action = .EditUIElement });
    }
}

fn Rebuild(self: *ComponentsPanel, engine_context: *EngineContext, object: SelectedObject, present: u64) !void {
    const zone = Tracy.ZoneInit("ComponentsPanel::Rebuild", @src());
    defer zone.Deinit();
    //every list but the one about to be built, which takes itself away as it builds: that way it keeps which of its
    //headers are open while it is built again for the same object
    if (object != .entity) try self.mEntityList.Clear(engine_context);
    if (object != .scene_layer) try self.mSceneList.Clear(engine_context);
    if (object != .player) try self.mPlayerList.Clear(engine_context);
    if (object != .gamecontext) try self.mGameContextList.Clear(engine_context);
    self.mButtons.clearRetainingCapacity();
    self.mBodyType = null;
    self.mPossessBox = null;
    self.mBuiltFor = object;
    self.mBuiltPresent = present;
    switch (object) {
        .entity => |entity| try self.mEntityList.Build(engine_context, self.mArea, self.mArea, entity, self.mOptions, self),
        .scene_layer => |scene| try self.mSceneList.Build(engine_context, self.mArea, self.mArea, scene, self.mOptions, self),
        .player => |player| try self.mPlayerList.Build(engine_context, self.mArea, self.mArea, player, self.mOptions, self),
        .gamecontext => |game_context| try self.mGameContextList.Build(engine_context, self.mArea, self.mArea, game_context, self.mOptions, self),
    }
    try self.mArea.MarkLayoutDirty(engine_context);
}

/// Takes every component list away, and what was added under them
fn Clear(self: *ComponentsPanel, engine_context: *EngineContext) !void {
    try self.mEntityList.Clear(engine_context);
    try self.mSceneList.Clear(engine_context);
    try self.mPlayerList.Clear(engine_context);
    try self.mGameContextList.Clear(engine_context);
    self.mButtons.clearRetainingCapacity();
    self.mBodyType = null;
    self.mPossessBox = null;
    self.mBuiltFor = null;
}

/// Whether the selected object's list asked to be built again, by a field that decides what else is shown
fn TakeRebuild(self: *ComponentsPanel, engine_context: *EngineContext) bool {
    const root = switch (self.mBuiltFor.?) {
        .entity => self.mEntityList.mRoot,
        .scene_layer => self.mSceneList.mRoot,
        .player => self.mPlayerList.mRoot,
        .gamecontext => self.mGameContextList.mRoot,
    } orelse return false;
    return engine_context.mUIManager.TakeRebuild(root);
}

/// Which of its list's components the object has, as bits
fn PresentOf(object: SelectedObject) u64 {
    return switch (object) {
        .entity => |entity| EntityList.PresentOf(entity).mask,
        .scene_layer => |scene| SceneList.PresentOf(scene).mask,
        .player => |player| PlayerList.PresentOf(player).mask,
        .gamecontext => |game_context| GameContextList.PresentOf(game_context).mask,
    };
}

fn ListAction(list_action: anytype) ?Action {
    const action = list_action orelse return null;
    return switch (action) {
        .Add => |index| .{ .Add = index },
        .Delete => |index| .{ .Delete = index },
    };
}

fn ToListAction(comptime List: type, action: Action) List.Action {
    return switch (action) {
        .Add => |index| .{ .Add = index },
        .Delete => |index| .{ .Delete = index },
        else => unreachable,
    };
}

fn IsActive(object: SelectedObject) bool {
    return switch (object) {
        inline else => |typed| typed.IsActive(),
    };
}

/// An object's name, up to the first 0 if it was saved with one
fn NameOf(object: SelectedObject) []const u8 {
    const name = switch (object) {
        inline else => |typed| typed.GetName(),
    };
    return name[0 .. std.mem.indexOfScalar(u8, name, 0) orelse name.len];
}

fn SameObject(a: SelectedObject, b: SelectedObject) bool {
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
    return switch (a) {
        inline else => |typed, tag| typed.mID == @field(b, @tagName(tag)).mID and typed.mManager == @field(b, @tagName(tag)).mManager,
    };
}

fn Same(a: Entity, b: Entity) bool {
    return a.mID == b.mID and a.mManager == b.mManager;
}

/// Puts `text` on a line, folded away while it says nothing
fn ShowLine(engine_context: *EngineContext, line: Entity, text: []const u8) !void {
    try WidgetActions.SetText(engine_context, line, text);
    const item = line.GetComponent(LayoutItemComponent).?;
    const hidden = text.len == 0;
    if (item.mCollapsed == hidden) return;
    item.mCollapsed = hidden;
    try line.MarkLayoutDirty(engine_context);
}

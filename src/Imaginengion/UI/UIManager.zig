//! UI land: everything about an entity's UI that only the UI uses. Entities stay the drivers of the game and keep what
//! other systems also use (layout, clips, pointer tags); what is UI and nothing else lives here instead, the way the
//! audio manager keeps voices apart from the AudioComponents that start them:
//!   - an ECS of UI elements (UIElement.zig), each the UI side of one entity, which holds the UI-only components
//!     (UIComponents.zig). An entity has one through its UIElementComponent, and its element points back at it
//!   - an event manager for what the UI does (Events/UIEventData.zig)
//!   - the parts that do the UI: typing into text inputs (FocusSystem), popups (PopupSystem), scrolling
//!     (ScrollSystem), number fields (NumberFieldSystem) and how things look (StyleSystem, out of the current theme)
//!
//! An element is never left without its entity, or shared by two. Every way an entity gets its component goes through
//! Adopt, which hands it a fresh element if it has none and points the element back at it: added in the panel or from
//! code, read from a file, copied from a template (Manager.AddComponent), duplicated (Manager.Duplicate) and copied
//! with its whole world (WorldManager.Copy). The other way round, an element whose entity is gone or has moved on is
//! deleted at the end of the frame (EndFrame).
//!
//! The program running the frame only talks to the UI through here, at these points of the frame:
//!   - OnInputEvent for the window's input events, after the pointer system has had them; key presses go through
//!     KeyTakerFor and OnKeyTaken instead, since they are handed out scene by scene
//!   - OnPointerEvent for each of the frame's pointer events, then ProcessUIEvents for what the UI did with it all
//!   - UpdateBeforeLayout once game logic has run, and UpdateAfterLayout once layout has, before world transforms
//!   - EndFrame at the end of the frame, and Reset when the world being played is thrown away
const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const WorldManager = @import("../Core/WorldManager.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const UIElement = @import("../ECSObjects/UIElement.zig");
const UIComponents = @import("../ECSComponents/UIComponents.zig");
const ElementOwnerComponent = UIComponents.ElementOwnerComponent;
const UIElementComponent = @import("../ECSComponents/EComponents.zig").UIElementComponent;
const TextComponent = @import("../ECSComponents/EComponents.zig").TextComponent;
const UIEventData = @import("../Events/UIEventData.zig");
const ECSManager = @import("../ECS/ECSManager.zig").ECSManager;
const EventManager = @import("../Events/EventManager.zig");
const EventResult = EventManager.EventResult;
const Tracy = @import("../Core/Tracy.zig");
const FocusSystem = @import("FocusSystem.zig");
const PopupSystem = @import("PopupSystem.zig");
const ScrollSystem = @import("ScrollSystem.zig");
const StyleSystem = @import("StyleSystem.zig");
const NumberFieldSystem = @import("NumberFieldSystem.zig");
const AssetHandle = @import("../ECSObjects/AssetHandle.zig");
const ThemeAsset = @import("../ECSComponents/AComponents.zig").ThemeAsset;
const ScrollComponent = UIComponents.ScrollComponent;
const ScrollStateComponent = UIComponents.ScrollStateComponent;
const WindowEventData = @import("../Events/WindowEventData.zig");
const PointerEvent = @import("../Events/PointerEventData.zig").EventT;
const PointerSystem = @import("../Pointer/PointerSystem.zig");
const ScanCodes = @import("../Inputs/InputEnums.zig").ScanCodes;

const UIManager = @This();

pub const ECSManagerT = ECSManager(UIElement.Type, &UIComponents.ComponentsList, "UIECS");
pub const EventManagerT = EventManager.EventManager(UIEventData);

const Core = @import("../ECSManagers/Manager.zig").Core(UIManager);

pub const empty: UIManager = .{};

mECSManager: ECSManagerT = .empty,
/// What the UI does (focus, typing, popups), and its own end of frame deletes
mEventManager: EventManagerT = .empty,
/// Which text input the keyboard is typing into, and the typing
mFocusSystem: FocusSystem = .empty,
/// Which popups are open, stacked
mPopupSystem: PopupSystem = .empty,
/// The mouse wheel and scrollbars of the elements that scroll
mScrollSystem: ScrollSystem = .empty,
/// How styled elements look
mStyleSystem: StyleSystem = .empty,
/// Dragging and typing number fields, and keeping their text showing their value
mNumberFieldSystem: NumberFieldSystem = .empty,
/// The current theme, which styles are looked up in. uninit until something asks for it, and then the engine's
/// default if no other has been set
mTheme: AssetHandle = .uninit,

/// The theme every project starts with
pub const DEFAULT_THEME_PATH = "src/Imaginengion/EngineAssets/themes/Default.imtheme";

pub fn Init(self: *UIManager, engine_allocator: std.mem.Allocator) !void {
    try self.mECSManager.Init(engine_allocator);
}

pub fn Deinit(self: *UIManager, engine_context: *EngineContext) void {
    self.mFocusSystem.Deinit(engine_context.EngineAllocator());
    self.mPopupSystem.Deinit(engine_context.EngineAllocator());
    self.mStyleSystem.Deinit(engine_context.EngineAllocator());
    self.mTheme.ReleaseAsset();
    self.mECSManager.Deinit(engine_context);
    self.mEventManager.Deinit(engine_context.EngineAllocator());
}

pub const SetSyncCallback = Core.SetSyncCallback;
pub const GetComponent = Core.GetComponent;
pub const HasComponent = Core.HasComponent;
pub const IsActiveObj = Core.IsActiveObj;
pub const GetGroup = Core.GetGroup;
pub const AddComponent = Core.AddComponent;
pub const RemoveComponent = Core.RemoveComponent;
pub const RemoveComponentSync = Core.RemoveComponentSync;
const DeleteObj = Core.DeleteObj;

//-----------------------------the frame-----------------------------

/// One of the window's input events, once the pointer system has had it, so a press lands on what the pointer is over.
/// A press closes the popups it is outside and moves the keyboard to what it landed on, typed text goes into the text
/// input that has the keyboard, and the wheel scrolls what is under the pointer
pub fn OnInputEvent(self: *UIManager, engine_context: *EngineContext, pointer: *const PointerSystem, event: WindowEventData.EventT) !void {
    switch (event) {
        .MousePressed => |e| {
            //popups first, so a text input in one that closes ends its edit before the keyboard moves on
            try self.mPopupSystem.OnPressed(engine_context, pointer);
            try self.mFocusSystem.OnPressed(engine_context, pointer, e._ButtonCode);
        },
        .TextTyped => |e| try self.mFocusSystem.OnTextTyped(engine_context, e.Text()),
        .MouseScrolled => |e| try self.mScrollSystem.OnWheel(engine_context, pointer, e._XOffset, e._YOffset),
        else => {},
    }
}

/// Which part of the UI takes a key, and at which turn in the scene stack: its scene's place
pub const KeyTaker = struct {
    StackPos: usize,
    Kind: enum {
        /// the text input with the keyboard: every key
        Focus,
        /// the top popup: Escape, which closes it
        Popup,
    },
};

/// Whether the UI takes `key`, and at which scene's turn. Keys are handed out scene by scene from the top of the stack:
/// whoever does that runs the scenes above the taker's first, and if none of them kept the key, hands it to OnKeyTaken.
/// The scenes below never hear it. A text input with the keyboard takes every key, the top popup takes Escape; the one
/// whose scene is higher goes first, and in the same scene the text input does, since it has the keyboard
pub fn KeyTakerFor(self: *const UIManager, key: ScanCodes) ?KeyTaker {
    const focus_pos = self.mFocusSystem.FocusedStackPos();
    const popup_pos = if (key == .ESCAPE) self.mPopupSystem.TopStackPos() else null;
    if (popup_pos) |pos| {
        if (focus_pos == null or pos > focus_pos.?) return .{ .StackPos = pos, .Kind = .Popup };
    }
    if (focus_pos) |pos| return .{ .StackPos = pos, .Kind = .Focus };
    return null;
}

/// The key reached the UI's turn and nothing above it kept it
pub fn OnKeyTaken(self: *UIManager, engine_context: *EngineContext, taker: KeyTaker, event: WindowEventData.KeyboardPressedEvent) !void {
    switch (taker.Kind) {
        .Focus => try self.mFocusSystem.OnKeyPressed(engine_context, event),
        .Popup => try self.mPopupSystem.CloseTop(engine_context),
    }
}

/// One of the frame's pointer events: a dragged scrollbar scrolls its region, a dragged number field changes its value,
/// and a double click can start typing
pub fn OnPointerEvent(self: *UIManager, engine_context: *EngineContext, event: PointerEvent) !void {
    try self.mScrollSystem.OnPointerEvent(engine_context, event);
    try self.mNumberFieldSystem.OnPointerEvent(engine_context, event);
    switch (event) {
        .PointerClicked => |e| try self.mFocusSystem.OnClicked(engine_context, e),
        else => {},
    }
}

/// Hands out what the UI did this frame (typing, popups, values) to `callback_list`, then empties it. The UI's own
/// parts have each event first (a number field takes the number typed into it), and what they send in turn is handed
/// out in the same pass
pub fn ProcessUIEvents(self: *UIManager, engine_context: *EngineContext, callback_list: std.DoublyLinkedList) !void {
    var own_callback = EventManagerT.MakeCallback(UIManager, OnOwnUIEvent, self);
    var callbacks = callback_list;
    callbacks.prepend(&own_callback.mNode);
    try self.mEventManager.ProcessCategory(.UI, engine_context, callbacks);
    self.mEventManager.ClearCategory(engine_context.EngineAllocator(), .UI, .ClearRetainingCapacity);
}

fn OnOwnUIEvent(self: *UIManager, engine_context: *EngineContext, event: *const UIEventData.EventT) !EventResult {
    try self.mNumberFieldSystem.OnUIEvent(engine_context, event.*);
    return .Continue;
}

/// Once a frame, after game logic and before layout (a font or a text can change sizes): every styled element's entity
/// takes its style out of the current theme, and every number field shows its value
pub fn UpdateBeforeLayout(self: *UIManager, engine_context: *EngineContext) !void {
    try self.mNumberFieldSystem.Update(engine_context);
    const theme = self.CurrentTheme(engine_context) orelse return;
    try self.mStyleSystem.Update(engine_context, theme);
}

/// Once a frame, after layout and before world transforms: open popups are placed against what opened them, scrollbars
/// put where their regions are scrolled to, and the caret where the laid out text puts it. Popups and scrollbars are
/// only for `play_world`, the world being played, null when nothing is
pub fn UpdateAfterLayout(self: *UIManager, engine_context: *EngineContext, play_world: ?*WorldManager) !void {
    if (play_world) |world| {
        try self.mPopupSystem.Update(engine_context, world);
        try self.mScrollSystem.Update(engine_context, world);
    }
    try self.mFocusSystem.Update(engine_context);
}

/// Forgets what the keyboard was typing into and the open popups without touching an entity, for when the world they
/// are in is about to be thrown away. Their elements go at the end of the frame, with their entities
pub fn Reset(self: *UIManager, engine_context: *EngineContext) void {
    self.mFocusSystem.Reset(engine_context);
    self.mPopupSystem.Reset();
    self.mNumberFieldSystem = .empty;
}

//------------------------------themes------------------------------

/// Makes `theme` the current theme, taking over the reference the handle holds. uninit goes back to the engine's
/// default
pub fn SetTheme(self: *UIManager, engine_context: *EngineContext, theme: AssetHandle) void {
    self.mTheme.ReleaseAsset();
    self.mTheme = theme;
    self.mStyleSystem.ClearWarnings(engine_context.EngineAllocator());
}

/// The current theme, loading the engine's default the first time if no other was set. Null if it can't be read, and
/// then nothing is styled
pub fn CurrentTheme(self: *UIManager, engine_context: *EngineContext) ?*ThemeAsset {
    if (!self.mTheme.IsIDValid()) {
        self.mTheme = engine_context.mAssetManager.GetAssetHandle(engine_context, .{ .File = .{ .rel_path = DEFAULT_THEME_PATH, .path_type = .Eng } }) catch |err| {
            std.log.err("The default theme could not be found: {s}", .{@errorName(err)});
            return null;
        };
    }
    return self.mTheme.GetAsset(engine_context, ThemeAsset) catch null;
}

/// The current theme is kept per project, see Project.zig
pub const ProjectSettingsName = "UI";

pub fn SaveProjectSettings(self: *UIManager, _: *EngineContext, write_stream: *std.json.Stringify) !void {
    try write_stream.beginObject();
    try write_stream.objectField("Theme");
    //the default is written as null, so a project keeps following it
    try write_stream.write(self.mTheme);
    try write_stream.endObject();
}

pub fn LoadProjectSettings(self: *UIManager, engine_context: *EngineContext, scanner: *std.json.Scanner) !void {
    try self.ResetProjectSettings(engine_context);

    if (.object_begin != try scanner.next()) return error.UnexpectedToken;
    while (true) {
        const key = switch (try scanner.nextAlloc(engine_context.FrameAllocator(), .alloc_if_needed)) {
            .object_end => break,
            inline .string, .allocated_string => |slice| slice,
            else => return error.UnexpectedToken,
        };
        if (std.mem.eql(u8, key, "Theme")) {
            const theme = try std.json.innerParse(AssetHandle, engine_context.FrameAllocator(), scanner, .{ .max_value_len = std.json.default_max_value_len });
            self.SetTheme(engine_context, theme);
        } else {
            std.log.warn("Skipping unknown key '{s}' in the UI settings", .{key});
            try scanner.skipValue();
        }
    }
}

/// Back to the engine's default theme
pub fn ResetProjectSettings(self: *UIManager, engine_context: *EngineContext) !void {
    self.SetTheme(engine_context, .uninit);
}

//------------------------------elements------------------------------

/// The manager an object of type obj_t is kept in. Lets code written for any object type reach this one the same way
pub fn GetManager(self: *UIManager, comptime obj_t: type) *UIManager {
    comptime std.debug.assert(obj_t == UIElement);
    return self;
}

/// A new element with no components of its own and no entity yet. Usually made through Adopt instead
pub fn NewElement(self: *UIManager, engine_context: *EngineContext) !UIElement {
    const engine_allocator = engine_context.EngineAllocator();
    const element_id = try self.mECSManager.CreateEntity(engine_allocator);
    _ = try self.mECSManager.AddComponent(engine_allocator, element_id, ElementOwnerComponent{});
    return .{ .mID = element_id, .mManager = self };
}

/// A new element with copies of `original`'s settings (its saved components), for a copied entity. A fresh, empty one
/// if there is no original
pub fn CopyElement(self: *UIManager, engine_context: *EngineContext, original: UIElement) !UIElement {
    const copy = try self.NewElement(engine_context);
    if (!original.IsActive()) return copy;
    inline for (UIComponents.SerializeList) |component_type| {
        if (original.GetComponent(component_type)) |component| {
            const value = if (@hasDecl(component_type, "Clone")) try component.Clone(engine_context) else component.*;
            _ = try copy.AddComponent(engine_context, value);
        }
    }
    return copy;
}

/// Deletes an element at the end of the frame
pub fn DeleteElement(self: *UIManager, engine_context: *EngineContext, element: UIElement) !void {
    try DeleteObj(self, engine_context, element.mID);
}

/// Makes `owner` the entity its UIElementComponent's element belongs to, first giving it a new element if it has
/// none. Every way an entity gets the component ends here
pub fn Adopt(self: *UIManager, engine_context: *EngineContext, owner: Entity) !void {
    const component = owner.GetComponent(UIElementComponent) orelse return;
    //a new element goes in this manager's ECS, so the entity's component stays where it is
    if (!component.mElement.IsActive()) component.mElement = try self.NewElement(engine_context);
    const element = component.mElement;
    element.GetComponent(ElementOwnerComponent).?.mOwner = owner;
    //what its components point at is in its entity's world: a copied world's ids carry over, so only the world changes
    if (element.GetComponent(UIComponents.PopupRefComponent)) |popup_ref| {
        if (popup_ref.mPopup.IsIDValid()) popup_ref.mPopup.mManager = owner.mManager;
    }
}

/// Adopt for every entity in a world, for one that has just been copied from another: its components were copied
/// with an element each, which still has no entity
pub fn AdoptWorld(self: *UIManager, engine_context: *EngineContext, world: *WorldManager) !void {
    const entity_ids = try world.GetEntityGroup(engine_context.FrameAllocator(), .{ .Component = UIElementComponent });
    for (entity_ids.items) |entity_id| try self.Adopt(engine_context, world.GetEntity(entity_id));
}

/// The UI element of an entity, null if it has none
pub fn ElementOf(entity: Entity) ?UIElement {
    const component = entity.GetComponent(UIElementComponent) orelse return null;
    return if (component.mElement.IsActive()) component.mElement else null;
}

/// One of an entity's UI components (UIComponents.zig), from its element. Null if it has no element, or its element
/// hasn't that component
pub fn GetUIComponent(entity: Entity, comptime component_type: type) ?*component_type {
    const element = ElementOf(entity) orelse return null;
    return element.GetComponent(component_type);
}

pub fn HasUIComponent(entity: Entity, comptime component_type: type) bool {
    const element = ElementOf(entity) orelse return false;
    return element.HasComponent(component_type);
}

/// One `kind` of UI event, about `target`, to it and to everything it is inside. For the events that are only an
/// entity and a target (ValueChanged, TextChanged, ...)
pub fn SendToChain(self: *UIManager, engine_context: *EngineContext, target: Entity, comptime kind: std.meta.Tag(UIEventData.EventT)) !void {
    var current = target;
    while (true) {
        const event = @unionInit(UIEventData.EventT, @tagName(kind), .{ .mEntity = current, .mTarget = target });
        try self.mEventManager.Insert(engine_context.EngineAllocator(), .UI, event);
        const child_component = current.GetComponent(@import("../ECS/Components.zig").ChildComponent(Entity.Type)) orelse break;
        current = Entity{ .mID = child_component.mParent, .mManager = current.mManager };
    }
}

/// The entity showing an entity's text: the entity itself if it has a TextComponent, otherwise its first child that
/// does. A number field's value, a button's or a row's label
pub fn LabelOf(entity: Entity) ?Entity {
    if (entity.HasComponent(TextComponent)) return entity;
    var children = entity.GetIterator(.Child);
    while (children.next()) |child| {
        if (child.HasComponent(TextComponent)) return child;
    }
    return null;
}

/// Gives `entity` the style called `style_name`, and a UI element to hold it if it has none
pub fn Style(engine_context: *EngineContext, entity: Entity, style_name: []const u8) !void {
    if (!entity.HasComponent(UIElementComponent)) _ = try entity.AddComponent(engine_context, UIElementComponent{});
    const element = ElementOf(entity).?;
    var style = try UIComponents.StyleComponent.Init(engine_context, style_name);
    errdefer style.Deinit(engine_context);
    if (element.GetComponent(UIComponents.StyleComponent)) |existing| {
        existing.Deinit(engine_context);
        existing.* = style;
    } else {
        _ = try element.AddComponent(engine_context, style);
    }
}

/// Called by Manager.AddComponent for every component an element gets: one that scrolls gets somewhere to keep how far
/// it is scrolled
pub fn OnElementComponentAdded(self: *UIManager, engine_context: *EngineContext, element_id: UIElement.Type, comptime component_type: type) !void {
    if (component_type == ScrollComponent and !self.mECSManager.HasComponent(ScrollStateComponent, element_id)) {
        _ = try self.mECSManager.AddComponent(engine_context.EngineAllocator(), element_id, ScrollStateComponent{});
    }
}

/// Once a frame, at its end: deletes every element its entity no longer points at (gone, its component removed, or
/// given another), and then whatever was asked to be deleted
pub fn EndFrame(self: *UIManager, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("UIManager::EndFrame", @src());
    defer zone.Deinit();

    const element_ids = try self.mECSManager.GetGroup(engine_context.FrameAllocator(), .{ .Component = ElementOwnerComponent });
    for (element_ids.items) |element_id| {
        const element = UIElement{ .mID = element_id, .mManager = self };
        if (!Owns(element.GetOwner(), element)) try self.DeleteElement(engine_context, element);
    }

    var callback_list: std.DoublyLinkedList = .{};
    var callback = EventManagerT.EventCallback{
        .mCtx = self,
        .mCallbackFn = struct {
            fn thunk(ctx: *anyopaque, ec: *EngineContext, event: *const UIEventData.EventT) anyerror!EventResult {
                return @as(*UIManager, @ptrCast(@alignCast(ctx))).OnManagerEvents(ec, event.*);
            }
        }.thunk,
    };
    callback_list.append(&callback.mNode);
    try self.mEventManager.ProcessCategory(.EndOfFrame, engine_context, callback_list);
    self.mEventManager.ClearCategory(engine_context.EngineAllocator(), .EndOfFrame, .ClearRetainingCapacity);

    var ecs_callbacks: std.DoublyLinkedList = .{};
    try self.mECSManager.ProcessEvents(engine_context, .EndOfFrame, &ecs_callbacks);
}

fn OnManagerEvents(self: *UIManager, engine_context: *EngineContext, event: UIEventData.EventT) anyerror!EventResult {
    switch (event) {
        .DestroyUIElement => |e| {
            if (self.mECSManager.IsActiveEntity(e.Element.mID)) try self.mECSManager.DestroyEntity(engine_context, e.Element.mID);
        },
        else => {},
    }
    return .Continue;
}

/// Whether `owner` is still there and its UIElementComponent still points at `element`
fn Owns(owner: Entity, element: UIElement) bool {
    if (!owner.IsActive()) return false;
    const component = owner.GetComponent(UIElementComponent) orelse return false;
    return component.mElement.mID == element.mID;
}

//! Popups: right-click menus, dropdown lists and the menus of a menu bar. A popup is a layout tree whose root has a
//! PopupComponent, built like any other UI. It is hidden while it is closed by its root's LayoutItemComponent being
//! collapsed, which hides the whole tree and keeps the pointer off it. Opening one expands it and places it against
//! what opened it (an entity, or a point such as where the pointer was), the way its PopupComponent says.
//!
//! Open popups are a stack, which is how submenus work:
//!   - opening a popup from an entity inside an open popup puts it on top of that one. Opening one from anywhere else
//!     closes the others first
//!   - a press of any button closes popups from the top down until it reaches one the press is inside, so pressing in
//!     a menu closes only its submenus and pressing outside every popup closes them all. The press carries on to what
//!     is under it either way: clicking a second dropdown while one is open opens the second straight away
//!   - Escape closes the top one, at its scene's turn in the scene stack
//!
//! A popup is placed every frame after layout, so it follows what opened it. It should be its own layout root: at the
//! top level of its scene (or under something that isn't a container), in the same scene as what opens it. Its
//! placement is the popup system's: leave its LayoutItemComponent's placement at Flow. Its z is yours, like the rest
//! of layout: give popups a z in front of the UI they open over.
const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const WorldManager = @import("../Core/WorldManager.zig");
const UIEvent = @import("../Events/UIEventData.zig").EventT;
const PointerSystem = @import("PointerSystem.zig");
const Layout = @import("Layout.zig");
const ShapeGeometry = @import("../Renderer/ShapeGeometry.zig");
const MathTypes = @import("../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;
const Vec3 = MathTypes.Vec3;

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const PopupComponent = EntityComponents.PopupComponent;
const LayoutItemComponent = EntityComponents.LayoutItemComponent;
const QuadComponent = EntityComponents.QuadComponent;
const TransformComponent = EntityComponents.TransformComponent;
const EntitySceneComponent = EntityComponents.EntitySceneComponent;
const EntityChildComponent = @import("../ECS/Components.zig").ChildComponent(Entity.Type);
const StackPosComponent = @import("../ECSComponents/SComponents.zig").StackPosComponent;

const PopupSystem = @This();

/// What a popup is placed against
pub const At = union(enum) {
    /// an entity's rectangle: a dropdown under its button, a submenu beside its row
    Opener: Entity,
    /// a point in the popup's scene, in its units (canvas units for an overlay): a right-click menu where the pointer
    /// was. PointerPoint works it out
    Point: Vec2(f32),
};

const OpenPopup = struct {
    mPopup: Entity,
    mAt: At,
};

pub const empty: PopupSystem = .{};

/// The open popups, from the bottom of the stack to the top
mOpen: std.ArrayList(OpenPopup) = .empty,

pub fn Deinit(self: *PopupSystem, engine_allocator: std.mem.Allocator) void {
    self.mOpen.deinit(engine_allocator);
    self.* = .empty;
}

/// Forgets every open popup without touching an entity, for when the world they are in is about to be thrown away
pub fn Reset(self: *PopupSystem) void {
    self.mOpen.clearRetainingCapacity();
}

/// The open popups, bottom of the stack first
pub fn OpenPopups(self: *const PopupSystem) []const OpenPopup {
    return self.mOpen.items;
}

pub fn IsOpen(self: *const PopupSystem, popup: Entity) bool {
    return self.IndexOf(popup) != null;
}

/// Opens `popup` placed against `at`. From an entity inside an open popup it goes on top of that one, closing what
/// was above it; otherwise every other popup closes first. Opening one that is already open moves it to `at` and
/// closes what is above it
pub fn Open(self: *PopupSystem, engine_context: *EngineContext, popup: Entity, at: At) !void {
    std.debug.assert(popup.HasComponent(PopupComponent));

    if (self.IndexOf(popup)) |index| {
        try self.CloseAbove(engine_context, index + 1);
        self.mOpen.items[index].mAt = at;
        return;
    }

    //what it opens on top of: the topmost open popup the opener is inside
    const keep = switch (at) {
        .Opener => |opener| self.TopmostContaining((try PointerSystem.ChainOf(engine_context.FrameAllocator(), opener)).items),
        .Point => null,
    };
    try self.CloseAbove(engine_context, if (keep) |index| index + 1 else 0);

    try self.mOpen.append(engine_context.EngineAllocator(), .{ .mPopup = popup, .mAt = at });
    try SetCollapsed(engine_context, popup, false);
    try Send(engine_context, popup, at, .PopupOpened);
}

/// Closes `popup` and every popup above it. Nothing happens if it isn't open
pub fn Close(self: *PopupSystem, engine_context: *EngineContext, popup: Entity) !void {
    const index = self.IndexOf(popup) orelse return;
    try self.CloseAbove(engine_context, index);
}

pub fn CloseAll(self: *PopupSystem, engine_context: *EngineContext) !void {
    try self.CloseAbove(engine_context, 0);
}

/// Closes the top popup, as Escape does
pub fn CloseTop(self: *PopupSystem, engine_context: *EngineContext) !void {
    if (self.mOpen.items.len == 0) return;
    try self.CloseAbove(engine_context, self.mOpen.items.len - 1);
}

/// Where the top popup's scene sits in the scene stack, which is its turn at Escape. Null if no popup is open
pub fn TopStackPos(self: *const PopupSystem) ?usize {
    if (self.mOpen.items.len == 0) return null;
    const top = self.mOpen.items[self.mOpen.items.len - 1].mPopup;
    if (!top.IsActive()) return null;
    const scene = top.GetComponent(EntitySceneComponent).?.mScene;
    const stack_pos = scene.GetComponent(StackPosComponent) orelse return 0;
    return stack_pos.mPosition;
}

/// Where the pointer is in `popup`'s scene, in its units, for opening it there (a right-click menu). Null if that
/// can't be worked out: an overlay popup needs the view the pointer is cast through, a world one something under it
pub fn PointerPoint(popup: Entity, pointer_input: PointerSystem.Input) ?Vec2(f32) {
    switch (popup.GetLayer()) {
        .OverlayLayer => {
            const view = pointer_input.View orelse return null;
            const scene = popup.GetComponent(EntitySceneComponent).?.mScene;
            const point = ShapeGeometry.SceneCanvas(scene, view.CameraView).RayToCanvasPoint(view.Ray) orelse return null;
            return .{ .x = point.x, .y = point.y };
        },
        .GameLayer => {
            if (pointer_input.Target == null) return null;
            return .{ .x = pointer_input.Position.x, .y = pointer_input.Position.y };
        },
    }
}

/// A mouse button went down on what the pointer system has it over: call it after the pointer system's OnPressed
/// and before the focus system's, so a text input in a popup this closes ends its edit first. Closes every popup
/// above the topmost one the press is inside
pub fn OnPressed(self: *PopupSystem, engine_context: *EngineContext, pointer: *const PointerSystem) !void {
    const keep = self.TopmostContaining(pointer.mHovered.items);
    try self.CloseAbove(engine_context, if (keep) |index| index + 1 else 0);
}

/// Once a frame, after layout and before world transforms: places each open popup against what opened it, and lets
/// go of popups that have been deleted. In `world`, every popup that isn't open is kept closed, so they all start
/// closed however they were saved
pub fn Update(self: *PopupSystem, engine_context: *EngineContext, world: *WorldManager) !void {
    //one deleted, and the ones opened from it go with it
    for (self.mOpen.items, 0..) |open, index| {
        if (!open.mPopup.IsActive()) {
            try self.CloseAbove(engine_context, index);
            break;
        }
    }

    const popups = try world.GetEntityGroup(engine_context.FrameAllocator(), .{ .Component = PopupComponent });
    for (popups.items) |popup_id| {
        const popup = world.GetEntity(popup_id);
        if (!self.IsOpen(popup)) try SetCollapsed(engine_context, popup, true);
    }

    for (self.mOpen.items) |open| try Place(engine_context, open);
}

/// Moves the popup's root to where its PopupComponent pins it against what opened it. Uses the size layout gave it
/// this frame, and where its opener was as of the last world transform pass
fn Place(engine_context: *EngineContext, open: OpenPopup) !void {
    const popup = open.mPopup;
    const anchoring = popup.GetComponent(PopupComponent).?.mPlacement;
    const size = if (popup.GetComponent(LayoutItemComponent)) |item| item.mComputedSize else Vec2(f32){ .x = 0, .y = 0 };

    const center: Vec2(f32) = switch (open.mAt) {
        .Point => |point| point.AddVec(Layout.AnchoredCenter(anchoring, .{ .x = 0, .y = 0 }, size)),
        .Opener => |opener| blk: {
            if (!opener.IsActive()) return;
            const transform = opener.GetComponent(TransformComponent) orelse return;
            const position = transform.GetWorldPosition();
            const opener_center = Vec2(f32){ .x = position.x, .y = position.y };
            break :blk opener_center.AddVec(Layout.AnchoredCenter(anchoring, RectSize(opener), size));
        },
    };

    //placed in its parent's space, if it has one
    const transform = popup.GetComponent(TransformComponent) orelse return;
    var local = Vec3(f32){ .x = center.x, .y = center.y, .z = 0 };
    if (popup.GetComponent(EntityChildComponent)) |child_component| {
        const parent = Entity{ .mID = child_component.mParent, .mManager = popup.mManager };
        if (parent.GetComponent(TransformComponent)) |parent_transform| {
            const scale = parent_transform.GetWorldScale();
            if (scale.x == 0 or scale.y == 0) return;
            const in_parent = local.SubVec(parent_transform.GetWorldPosition()).InvQuatRotate(parent_transform.GetWorldRotation());
            local = .{ .x = in_parent.x / scale.x, .y = in_parent.y / scale.y, .z = 0 };
        }
    }

    const current = transform.GetTranslation();
    if (current.x == local.x and current.y == local.y) return;
    try popup.SetTranslation(engine_context, .{ .x = local.x, .y = local.y, .z = current.z });
}

/// How big an opener's rectangle is: the size layout gave it, or else its quad's, grown by its scale
fn RectSize(opener: Entity) Vec2(f32) {
    var size = Vec2(f32){ .x = 0, .y = 0 };
    if (opener.GetComponent(LayoutItemComponent)) |item| {
        size = item.mComputedSize;
    } else if (opener.GetComponent(QuadComponent)) |quad| {
        size = quad.mSize;
    }
    const scale = if (opener.GetComponent(TransformComponent)) |transform| transform.GetWorldScale() else Vec3(f32){ .x = 1, .y = 1, .z = 1 };
    return .{ .x = size.x * scale.x, .y = size.y * scale.y };
}

/// Closes every popup from `index` up, the top one first
fn CloseAbove(self: *PopupSystem, engine_context: *EngineContext, index: usize) !void {
    while (self.mOpen.items.len > index) {
        const open = self.mOpen.pop().?;
        const popup = open.mPopup;
        if (!popup.IsActive()) continue;

        //a text input in it can't be typed into once it is hidden: its edit ends, kept
        if (engine_context.mFocusSystem.Focused()) |focused| {
            const chain = try PointerSystem.ChainOf(engine_context.FrameAllocator(), focused);
            if (Contains(chain.items, popup)) try engine_context.mFocusSystem.EndEdit(engine_context, .Submit);
        }

        try SetCollapsed(engine_context, popup, true);
        try Send(engine_context, popup, open.mAt, .PopupClosed);
    }
}

/// The index of the topmost open popup in `chain`, null if it holds none
fn TopmostContaining(self: *const PopupSystem, chain: []const Entity) ?usize {
    var index = self.mOpen.items.len;
    while (index > 0) {
        index -= 1;
        const popup = self.mOpen.items[index].mPopup;
        if (popup.IsActive() and Contains(chain, popup)) return index;
    }
    return null;
}

fn IndexOf(self: *const PopupSystem, popup: Entity) ?usize {
    for (self.mOpen.items, 0..) |open, index| {
        if (Same(open.mPopup, popup)) return index;
    }
    return null;
}

/// Opens or closes the popup's tree through its layout item, which it is given if it has none
fn SetCollapsed(engine_context: *EngineContext, popup: Entity, collapsed: bool) !void {
    const item = popup.GetComponent(LayoutItemComponent) orelse try popup.AddComponent(engine_context, LayoutItemComponent{});
    if (item.mCollapsed == collapsed) return;
    item.mCollapsed = collapsed;
    try popup.MarkLayoutDirty(engine_context);
}

/// One event of `kind` to the popup and to everything it is inside
fn Send(engine_context: *EngineContext, popup: Entity, at: At, comptime kind: std.meta.Tag(UIEvent)) !void {
    const opener: ?Entity = switch (at) {
        .Opener => |entity| entity,
        .Point => null,
    };
    const chain = try PointerSystem.ChainOf(engine_context.FrameAllocator(), popup);
    for (chain.items) |entity| {
        const event = @unionInit(UIEvent, @tagName(kind), .{ .mEntity = entity, .mTarget = popup, .mOpener = opener });
        try engine_context.mUIEventManager.Insert(engine_context.EngineAllocator(), .Interaction, event);
    }
}

fn Contains(chain: []const Entity, entity: Entity) bool {
    for (chain) |other| {
        if (Same(other, entity)) return true;
    }
    return false;
}

fn Same(a: Entity, b: Entity) bool {
    return a.mID == b.mID and a.mManager == b.mManager;
}

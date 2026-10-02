//! What the pointer (the mouse) is over, holding down and dragging, turned into things entities can react to:
//!   - states, as tags: HoveredTag while the pointer is over an entity, PressedTag while a button that went down
//!     on it is still held. Anything can check them, or query everything that has one
//!   - moments, as events through the engine's UI event manager (Events/UIEventData.zig): enter, exit, pressed,
//!     released, clicked, and a drag's start, moves and end
//!   - drag and drop: a drag that starts on a drag source (DragSourceComponent) can be let go over a drop target
//!     (DropTargetComponent) that takes it. What a source carries is its own components, and a target takes it if
//!     it has one the target lists. The target gets DropHoverTag while it's held over it, and PointerDropped on
//!     the drop
//!
//! All of it goes to the entity under the pointer and to everything it is inside: its parent, and so on up (its
//! chain). The pointer over a button's label is over the button, and inside the panel the button is in.
//!
//! It doesn't find what is under the pointer itself: whoever owns the views (the editor, a game's window) casts
//! the ray and hands over the entity it hit, so this works the same for an overlay and for the world.
const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const MouseCodes = @import("../Inputs/InputEnums.zig").MouseCodes;
const CLICK_DRAG_THRESHOLD = @import("../Inputs/Input.zig").CLICK_DRAG_THRESHOLD;
const MathTypes = @import("../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;
const Vec3 = MathTypes.Vec3;
const Ray = @import("../Math/CameraRay.zig").Ray;
const CameraView = @import("../Renderer/Renderer.zig").CameraView;
const ShapeGeometry = @import("../Renderer/ShapeGeometry.zig");
const UIEvent = @import("../Events/UIEventData.zig").EventT;

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const HoveredTag = EntityComponents.HoveredTag;
const PressedTag = EntityComponents.PressedTag;
const DropHoverTag = EntityComponents.DropHoverTag;
const DragSourceComponent = EntityComponents.DragSourceComponent;
const DropTargetComponent = EntityComponents.DropTargetComponent;
const EntitySceneComponent = EntityComponents.EntitySceneComponent;
const EntityChildComponent = @import("../ECS/Components.zig").ChildComponent(Entity.Type);

const PointerSystem = @This();

const Chain = std.ArrayList(Entity);
const ZERO = Vec3(f32){ .x = 0, .y = 0, .z = 0 };

/// What the pointer system is told once a frame
pub const Input = struct {
    /// the entity under the pointer, null if it is over nothing
    Target: ?Entity = null,
    /// where the pointer's ray met the target, in the world
    Position: Vec3(f32) = ZERO,
    /// the mouse in window pixels, which is what tells a drag from a click
    Pixel: Vec2(f32) = .{ .x = 0, .y = 0 },
    /// the view the pointer is cast through, which a drag follows the pointer across. Null when there is none:
    /// a drag then waits where it is until there is one again
    View: ?View = null,
};

/// The pointer's ray, and the camera of the view it is cast through
pub const View = struct {
    Ray: Ray,
    CameraView: CameraView,
};

/// A mouse button that is down, and what it went down on
const Held = struct {
    /// what it went down on: the entity under the pointer first, then each thing it is inside
    mChain: Chain = .empty,
    mPressPixel: Vec2(f32) = .{ .x = 0, .y = 0 },
    /// where the pointer's ray met that entity, in the world
    mGrabPosition: Vec3(f32) = ZERO,
    /// the pointer has moved far enough from where the button went down that this is a drag, not a click
    mIsDragging: bool = false,
    /// where the pointer was on the drag plane when the button went down, and as of the last drag event, in the
    /// grabbed entity's own units (see DragPoint). Null until there has been a view to work it out through
    mStartPoint: ?Vec3(f32) = null,
    mLastPoint: ?Vec3(f32) = null,
    /// for a drag of the left button that started on a drag source: the nearest one it went down on
    mSource: ?Entity = null,
};

/// The button drag and drop uses: other buttons still drag, they just carry nothing
const DROP_BUTTON: MouseCodes = .BUTTON_LEFT;

pub const empty: PointerSystem = .{};

/// What the pointer is over, the entity itself first and then each thing it is inside. Kept as a list rather than
/// worked out from the first entity again, so the rest still hear the pointer leave if that entity is deleted
mHovered: Chain = .empty,
/// What the last Update was told, which is what a press lands on
mInput: Input = .{},
mHeld: std.EnumArray(MouseCodes, Held) = .initFill(.{}),
/// What each button was on when it last came up, for the click that may follow the release
mReleased: std.EnumArray(MouseCodes, Chain) = .initFill(.empty),
/// Whether each button's last release ended a drag, which is never a click as well
mWasDragged: std.EnumArray(MouseCodes, bool) = .initFill(false),
/// The drop target with DropHoverTag: what the held drag source would be dropped on if let go now
mDropTarget: ?Entity = null,

pub fn Deinit(self: *PointerSystem, engine_allocator: std.mem.Allocator) void {
    self.mHovered.deinit(engine_allocator);
    for (&self.mHeld.values) |*held| held.mChain.deinit(engine_allocator);
    for (&self.mReleased.values) |*chain| chain.deinit(engine_allocator);
    self.* = .empty;
}

/// Forgets everything without touching an entity, for when the world they are in is about to be thrown away
pub fn Reset(self: *PointerSystem) void {
    self.mHovered.clearRetainingCapacity();
    for (&self.mHeld.values) |*held| {
        held.mChain.clearRetainingCapacity();
        held.mIsDragging = false;
    }
    for (&self.mReleased.values) |*chain| chain.clearRetainingCapacity();
    self.mDropTarget = null;
}

/// What the left button is carrying: the drag source of the drag in progress, null if there is none
pub fn Carrying(self: *const PointerSystem) ?Entity {
    const held = self.mHeld.get(DROP_BUTTON);
    if (!held.mIsDragging) return null;
    const source = held.mSource orelse return null;
    return if (source.IsActive()) source else null;
}

/// Whether any mouse button is down on something
pub fn IsHolding(self: *const PointerSystem) bool {
    for (self.mHeld.values) |held| {
        if (held.mChain.items.len > 0) return true;
    }
    return false;
}

/// Once a frame: where the pointer is and what is under it. Checked every frame rather than only when the mouse
/// moves, since what is under a still mouse can move, appear or go away
pub fn Update(self: *PointerSystem, engine_context: *EngineContext, input: Input) !void {
    self.mInput = input;
    try self.UpdateHover(engine_context);
    for (std.enums.values(MouseCodes)) |button| try self.UpdateDrag(engine_context, button);
    try self.UpdateDropTarget(engine_context);
}

/// Moves DropHoverTag to whatever the drag source would be dropped on now
fn UpdateDropTarget(self: *PointerSystem, engine_context: *EngineContext) !void {
    const new_target: ?Entity = if (self.Carrying()) |source| FindDropTarget(self.mHovered.items, source) else null;
    try self.SetDropTarget(engine_context, new_target);
}

fn SetDropTarget(self: *PointerSystem, engine_context: *EngineContext, new_target: ?Entity) !void {
    if (self.mDropTarget) |old| {
        if (new_target != null and Same(old, new_target.?)) return;
        if (old.IsActive() and old.HasComponent(DropHoverTag)) try old.RemoveComponentSync(engine_context, DropHoverTag);
    }
    self.mDropTarget = new_target;
    if (new_target) |target| {
        if (!target.HasComponent(DropHoverTag)) _ = try target.AddComponent(engine_context, DropHoverTag{});
    }
}

/// The nearest drop target in `chain` (what the pointer is over, then each thing it is inside) that takes `source`.
/// A source isn't dropped on itself
fn FindDropTarget(chain: []const Entity, source: Entity) ?Entity {
    for (chain) |entity| {
        if (!entity.IsActive() or Same(entity, source)) continue;
        const drop_target = entity.GetComponent(DropTargetComponent) orelse continue;
        if (Takes(drop_target.*, source)) return entity;
    }
    return null;
}

/// Whether the source has any of the components the target takes
fn Takes(drop_target: DropTargetComponent, source: Entity) bool {
    const ecs = &source.mManager.mEManager.mECSManager;
    for (drop_target.mAccepts) |component_ind| {
        if (ecs.HasComponentInd(component_ind, source.mID)) return true;
    }
    return false;
}

fn UpdateHover(self: *PointerSystem, engine_context: *EngineContext) !void {
    const new_chain = try ChainOf(engine_context.FrameAllocator(), self.mInput.Target);

    //left: in the old chain and not the new one. The ones that are gone altogether have nothing left to tell
    for (self.mHovered.items) |entity| {
        if (!entity.IsActive() or Contains(new_chain.items, entity)) continue;
        if (entity.HasComponent(HoveredTag)) try entity.RemoveComponentSync(engine_context, HoveredTag);
        try Send(engine_context, .{ .PointerExit = .{ .mEntity = entity } });
    }
    //entered: in the new chain and not the old one
    for (new_chain.items) |entity| {
        if (Contains(self.mHovered.items, entity)) continue;
        if (!entity.HasComponent(HoveredTag)) _ = try entity.AddComponent(engine_context, HoveredTag{});
        try Send(engine_context, .{ .PointerEnter = .{ .mEntity = entity } });
    }

    try Assign(&self.mHovered, engine_context.EngineAllocator(), new_chain.items);
}

/// A held button becomes a drag once the mouse is CLICK_DRAG_THRESHOLD from where it went down, the same distance
/// the input manager stops calling a release a click at. From then on what it holds hears how the pointer moves
fn UpdateDrag(self: *PointerSystem, engine_context: *EngineContext, button: MouseCodes) !void {
    const held = self.mHeld.getPtr(button);
    const target = if (held.mChain.items.len > 0) held.mChain.items[0] else return;

    if (!held.mIsDragging) {
        if (self.mInput.Pixel.Distance(held.mPressPixel) < CLICK_DRAG_THRESHOLD) return;
        held.mIsDragging = true;
        //picked up: the nearest drag source it went down on
        if (button == DROP_BUTTON) {
            for (held.mChain.items) |entity| {
                if (entity.IsActive() and entity.HasComponent(DragSourceComponent)) {
                    held.mSource = entity;
                    break;
                }
            }
        }
        for (held.mChain.items) |entity| {
            if (!entity.IsActive()) continue;
            try Send(engine_context, .{ .PointerDragStart = .{ .mEntity = entity, .mButton = button, .mTarget = target } });
        }
    }

    const point = DragPoint(held.*, self.mInput) orelse return;
    //no view yet when the button went down: the drag is measured from the first point there is
    const start = held.mStartPoint orelse point;
    const last = held.mLastPoint orelse point;
    held.mStartPoint = start;
    held.mLastPoint = point;

    const delta = point.SubVec(last);
    if (delta.x == 0 and delta.y == 0 and delta.z == 0) return;
    for (held.mChain.items) |entity| {
        if (!entity.IsActive()) continue;
        try Send(engine_context, .{ .PointerDrag = .{
            .mEntity = entity,
            .mButton = button,
            .mDelta = delta,
            .mTotal = point.SubVec(start),
            .mTarget = target,
        } });
    }
}

/// Where the pointer is on the plane a drag is measured across, in the units the grabbed entity is placed in, so
/// something dragged can add a drag's delta to its own translation and stay under the pointer:
///   - an overlay entity: the point on its scene's canvas, in canvas units
///   - a world entity: the point on the plane facing the camera through where it was grabbed, in world units
fn DragPoint(held: Held, input: Input) ?Vec3(f32) {
    const view = input.View orelse return null;
    const target = held.mChain.items[0];
    if (!target.IsActive()) return null;

    switch (target.GetLayer()) {
        .OverlayLayer => {
            const scene = target.GetComponent(EntitySceneComponent).?.mScene;
            return ShapeGeometry.SceneCanvas(scene, view.CameraView).RayToCanvasPoint(view.Ray);
        },
        .GameLayer => {
            const normal = (Vec3(f32){ .x = 0, .y = 0, .z = 1 }).QuatRotate(view.CameraView.Pose.Rotation);
            const facing = view.Ray.Dir.Dot(normal);
            if (facing == 0) return null;
            const t = held.mGrabPosition.SubVec(view.Ray.Origin).Dot(normal) / facing;
            if (t < 0) return null;
            return view.Ray.Origin.AddVec(view.Ray.Dir.MulScalar(t));
        },
    }
}

/// A mouse button went down: on whatever the pointer is over as of the last Update
pub fn OnPressed(self: *PointerSystem, engine_context: *EngineContext, button: MouseCodes) !void {
    const held = self.mHeld.getPtr(button);
    try Assign(&held.mChain, engine_context.EngineAllocator(), self.mHovered.items);
    held.mPressPixel = self.mInput.Pixel;
    held.mGrabPosition = self.mInput.Position;
    held.mIsDragging = false;
    held.mStartPoint = null;
    held.mLastPoint = null;
    held.mSource = null;

    const target = if (held.mChain.items.len > 0) held.mChain.items[0] else return;
    //where a drag would be measured from
    held.mStartPoint = DragPoint(held.*, self.mInput);
    held.mLastPoint = held.mStartPoint;

    for (held.mChain.items) |entity| {
        if (!entity.IsActive()) continue;
        if (!entity.HasComponent(PressedTag)) _ = try entity.AddComponent(engine_context, PressedTag{});
        try Send(engine_context, .{ .PointerPressed = .{ .mEntity = entity, .mButton = button, .mPosition = self.mInput.Position, .mTarget = target } });
    }
}

/// A mouse button came up: whatever it went down on is let go, wherever the pointer is now, and its drag ends
pub fn OnReleased(self: *PointerSystem, engine_context: *EngineContext, button: MouseCodes) !void {
    const held = self.mHeld.getPtr(button);
    //kept for the click that follows a release in place
    try Assign(self.mReleased.getPtr(button), engine_context.EngineAllocator(), held.mChain.items);
    const released = self.mReleased.get(button).items;
    const was_dragging = held.mIsDragging;
    const total = if (held.mStartPoint != null and held.mLastPoint != null) held.mLastPoint.?.SubVec(held.mStartPoint.?) else ZERO;
    self.mWasDragged.set(button, was_dragging);

    //let go over something that takes what it carries: dropped there
    if (button == DROP_BUTTON) {
        if (self.Carrying()) |source| {
            if (self.mDropTarget) |drop_target| {
                if (drop_target.IsActive()) try Send(engine_context, .{ .PointerDropped = .{ .mEntity = drop_target, .mSource = source, .mPosition = self.mInput.Position } });
            }
        }
        try self.SetDropTarget(engine_context, null);
        held.mSource = null;
    }

    held.mChain.clearRetainingCapacity();
    held.mIsDragging = false;

    const target = if (released.len > 0) released[0] else return;
    for (released) |entity| {
        if (!entity.IsActive()) continue;
        //another button may still be holding it
        if (!self.IsHeld(entity) and entity.HasComponent(PressedTag)) try entity.RemoveComponentSync(engine_context, PressedTag);
        if (was_dragging) try Send(engine_context, .{ .PointerDragEnd = .{ .mEntity = entity, .mButton = button, .mTotal = total, .mTarget = target } });
        try Send(engine_context, .{ .PointerReleased = .{ .mEntity = entity, .mButton = button, .mPosition = self.mInput.Position, .mTarget = target } });
    }
}

/// The release just before this was a click (the input manager's: the button came up where it went down). It
/// clicks what was under the pointer both when the button went down and now: pressing on a button's label and
/// letting go on its background clicks the button, which was under both, but not the label. A release that ended
/// a drag clicks nothing, even if the pointer came back to where it started
pub fn OnClicked(self: *PointerSystem, engine_context: *EngineContext, button: MouseCodes, clicks: u8) !void {
    const released = self.mReleased.getPtr(button);
    defer released.clearRetainingCapacity();
    if (self.mWasDragged.get(button)) return;

    const target = if (self.mHovered.items.len > 0) self.mHovered.items[0] else return;
    for (released.items) |entity| {
        if (!entity.IsActive() or !Contains(self.mHovered.items, entity)) continue;
        try Send(engine_context, .{ .PointerClicked = .{
            .mEntity = entity,
            .mButton = button,
            .mClicks = clicks,
            .mPosition = self.mInput.Position,
            .mTarget = target,
        } });
    }
}

/// Whether any button that is down went down on `entity`
fn IsHeld(self: *const PointerSystem, entity: Entity) bool {
    for (self.mHeld.values) |held| {
        if (Contains(held.mChain.items, entity)) return true;
    }
    return false;
}

/// `entity` and then each thing it is inside, up to the top of its hierarchy. Empty for null
pub fn ChainOf(frame_allocator: std.mem.Allocator, entity: ?Entity) !Chain {
    var chain: Chain = .empty;
    var current = entity orelse return chain;
    if (!current.IsActive()) return chain;
    while (true) {
        try chain.append(frame_allocator, current);
        const child_component = current.GetComponent(EntityChildComponent) orelse break;
        current = Entity{ .mID = child_component.mParent, .mManager = current.mManager };
    }
    return chain;
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

fn Assign(chain: *Chain, engine_allocator: std.mem.Allocator, entities: []const Entity) !void {
    chain.clearRetainingCapacity();
    try chain.appendSlice(engine_allocator, entities);
}

fn Send(engine_context: *EngineContext, event: UIEvent) !void {
    try engine_context.mUIEventManager.Insert(engine_context.EngineAllocator(), .Interaction, event);
}

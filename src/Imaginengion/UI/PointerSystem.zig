//! What the pointer (the mouse) is over and holding down, turned into things entities can react to:
//!   - states, as tags: HoveredTag while the pointer is over an entity, PressedTag while a button that went down
//!     on it is still held. Anything can check them, or query everything that has one
//!   - moments, as events through the engine's UI event manager (Events/UIEventData.zig): enter, exit, pressed,
//!     released, clicked
//!
//! Both go to the entity under the pointer and to everything it is inside: its parent, and so on up (its chain).
//! The pointer over a button's label is over the button, and inside the panel the button is in.
//!
//! It doesn't find what is under the pointer itself: whoever owns the views (the editor, a game's window) casts
//! the ray and hands over the entity it hit, so this works the same for an overlay and for the world.
const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const MouseCodes = @import("../Inputs/InputEnums.zig").MouseCodes;
const Vec3 = @import("../Math/MathTypes.zig").Vec3;

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const HoveredTag = EntityComponents.HoveredTag;
const PressedTag = EntityComponents.PressedTag;
const EntityChildComponent = @import("../ECS/Components.zig").ChildComponent(Entity.Type);

const PointerSystem = @This();

const Chain = std.ArrayList(Entity);

pub const empty: PointerSystem = .{};

/// What the pointer is over, the entity itself first and then each thing it is inside. Kept as a list rather than
/// worked out from the first entity again, so the rest still hear the pointer leave if that entity is deleted
mHovered: Chain = .empty,
mHoverPosition: Vec3(f32) = .{ .x = 0, .y = 0, .z = 0 },
/// What each held button went down on, the same way
mPressed: std.EnumArray(MouseCodes, Chain) = .initFill(.empty),
/// What each button was on when it last came up, for the click that may follow the release
mReleased: std.EnumArray(MouseCodes, Chain) = .initFill(.empty),

pub fn Deinit(self: *PointerSystem, engine_allocator: std.mem.Allocator) void {
    self.mHovered.deinit(engine_allocator);
    for (&self.mPressed.values) |*chain| chain.deinit(engine_allocator);
    for (&self.mReleased.values) |*chain| chain.deinit(engine_allocator);
    self.* = .empty;
}

/// Forgets everything without touching an entity, for when the world they are in is about to be thrown away
pub fn Reset(self: *PointerSystem) void {
    self.mHovered.clearRetainingCapacity();
    for (&self.mPressed.values) |*chain| chain.clearRetainingCapacity();
    for (&self.mReleased.values) |*chain| chain.clearRetainingCapacity();
}

/// Once a frame: `target` is the entity under the pointer, null if it is over nothing, and `position` where its
/// ray met it. Checked every frame rather than only when the mouse moves, since what is under a still mouse can
/// move, appear or go away
pub fn UpdateHover(self: *PointerSystem, engine_context: *EngineContext, target: ?Entity, position: Vec3(f32)) !void {
    const frame_allocator = engine_context.FrameAllocator();
    const new_chain = try ChainOf(frame_allocator, target);
    self.mHoverPosition = position;

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

/// A mouse button went down: on whatever the pointer is over as of the last UpdateHover
pub fn OnPressed(self: *PointerSystem, engine_context: *EngineContext, button: MouseCodes) !void {
    const pressed = self.mPressed.getPtr(button);
    try Assign(pressed, engine_context.EngineAllocator(), self.mHovered.items);

    const target = if (pressed.items.len > 0) pressed.items[0] else return;
    for (pressed.items) |entity| {
        if (!entity.IsActive()) continue;
        if (!entity.HasComponent(PressedTag)) _ = try entity.AddComponent(engine_context, PressedTag{});
        try Send(engine_context, .{ .PointerPressed = .{ .mEntity = entity, .mButton = button, .mPosition = self.mHoverPosition, .mTarget = target } });
    }
}

/// A mouse button came up: whatever it went down on is let go, wherever the pointer is now
pub fn OnReleased(self: *PointerSystem, engine_context: *EngineContext, button: MouseCodes) !void {
    const pressed = self.mPressed.getPtr(button);
    //kept for the click that follows a release in place
    try Assign(self.mReleased.getPtr(button), engine_context.EngineAllocator(), pressed.items);
    const released = self.mReleased.get(button).items;
    pressed.clearRetainingCapacity();

    const target = if (released.len > 0) released[0] else return;
    for (released) |entity| {
        if (!entity.IsActive()) continue;
        //another button may still be holding it
        if (!self.IsHeld(entity) and entity.HasComponent(PressedTag)) try entity.RemoveComponentSync(engine_context, PressedTag);
        try Send(engine_context, .{ .PointerReleased = .{ .mEntity = entity, .mButton = button, .mPosition = self.mHoverPosition, .mTarget = target } });
    }
}

/// The release just before this was a click (the input manager's: the button came up where it went down). It
/// clicks what was under the pointer both when the button went down and now: pressing on a button's label and
/// letting go on its background clicks the button, which was under both, but not the label
pub fn OnClicked(self: *PointerSystem, engine_context: *EngineContext, button: MouseCodes, clicks: u8) !void {
    const released = self.mReleased.getPtr(button);
    defer released.clearRetainingCapacity();

    const target = if (self.mHovered.items.len > 0) self.mHovered.items[0] else return;
    for (released.items) |entity| {
        if (!entity.IsActive() or !Contains(self.mHovered.items, entity)) continue;
        try Send(engine_context, .{ .PointerClicked = .{
            .mEntity = entity,
            .mButton = button,
            .mClicks = clicks,
            .mPosition = self.mHoverPosition,
            .mTarget = target,
        } });
    }
}

/// Whether any button that is down went down on `entity`
fn IsHeld(self: *const PointerSystem, entity: Entity) bool {
    for (self.mPressed.values) |chain| {
        if (Contains(chain.items, entity)) return true;
    }
    return false;
}

/// `entity` and then each thing it is inside, up to the top of its hierarchy. Empty for null
fn ChainOf(frame_allocator: std.mem.Allocator, entity: ?Entity) !Chain {
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
        if (other.mID == entity.mID and other.mManager == entity.mManager) return true;
    }
    return false;
}

fn Assign(chain: *Chain, engine_allocator: std.mem.Allocator, entities: []const Entity) !void {
    chain.clearRetainingCapacity();
    try chain.appendSlice(engine_allocator, entities);
}

fn Send(engine_context: *EngineContext, event: @import("../Events/UIEventData.zig").EventT) !void {
    try engine_context.mUIEventManager.Insert(engine_context.EngineAllocator(), .Pointer, event);
}

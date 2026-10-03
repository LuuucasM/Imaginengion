//! Scrolling: the mouse wheel and scrollbars of the entities whose UI element scrolls (ScrollComponent). How far one is
//! scrolled is its element's ScrollStateComponent, which layout moves the entity's children by and keeps in range;
//! this only changes it and asks for another layout pass.
//!   - the wheel scrolls the nearest region under the pointer that scrolls that way, even one already at its end
//!   - a region whose children run past it shows a scrollbar thumb along that edge: a quad on a child entity, made
//!     and deleted here like the text caret. Its length shows how much is in view, its place how far it is scrolled,
//!     and dragging it scrolls
const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const UIElement = @import("../ECSObjects/UIElement.zig");
const WorldManager = @import("../Core/WorldManager.zig");
const PointerEvent = @import("../Events/PointerEventData.zig").EventT;
const PointerSystem = @import("../Pointer/PointerSystem.zig");
const UIManager = @import("UIManager.zig");
const Layout = @import("Layout.zig");
const MathTypes = @import("../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;
const Vec3 = MathTypes.Vec3;

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const LayoutItemComponent = EntityComponents.LayoutItemComponent;
const QuadComponent = EntityComponents.QuadComponent;
const NameComponent = EntityComponents.NameComponent;
const TransformComponent = EntityComponents.TransformComponent;
const EntityChildComponent = @import("../ECS/Components.zig").ChildComponent(Entity.Type);
const UIComponents = @import("../ECSComponents/UIComponents.zig");
const ScrollComponent = UIComponents.ScrollComponent;
const ScrollStateComponent = UIComponents.ScrollStateComponent;

const ScrollSystem = @This();

/// How thick a scrollbar is, in the region's units
pub const THUMB_THICKNESS: f32 = 8;
/// The shortest a thumb gets however much there is to scroll, so it can still be grabbed
pub const THUMB_MIN_LENGTH: f32 = 20;
/// How far in front of the region the thumb sits, so it is drawn over its children
const THUMB_DEPTH: f32 = 0.02;

pub const empty: ScrollSystem = .{};

/// The mouse wheel turned while the pointer is over what the pointer system has it over. Notches up (y) scroll up,
/// notches right (x) scroll right
pub fn OnWheel(_: *ScrollSystem, engine_context: *EngineContext, pointer: *const PointerSystem, notches_x: f32, notches_y: f32) !void {
    if (notches_y != 0) {
        if (NearestScrolling(pointer.mHovered.items, .Y)) |region| try ScrollBy(engine_context, region, .{ .x = 0, .y = -notches_y * Step(region) });
    }
    if (notches_x != 0) {
        if (NearestScrolling(pointer.mHovered.items, .X)) |region| try ScrollBy(engine_context, region, .{ .x = notches_x * Step(region), .y = 0 });
    }
}

/// A frame's pointer events: a scrollbar thumb being dragged scrolls its region, as much as keeps the thumb under the
/// pointer
pub fn OnPointerEvent(_: *ScrollSystem, engine_context: *EngineContext, event: PointerEvent) !void {
    const drag = switch (event) {
        .PointerDrag => |drag| drag,
        else => return,
    };
    //one event per entity in the chain: only the thumb's own
    if (drag.mEntity.mID != drag.mTarget.mID or drag.mEntity.mManager != drag.mTarget.mManager) return;
    if (drag.mButton != .BUTTON_LEFT) return;

    const thumb = drag.mTarget;
    if (!thumb.IsActive()) return;
    const region = Parent(thumb) orelse return;
    const state = UIManager.GetUIComponent(region, ScrollStateComponent) orelse return;
    const axis: Layout.Axis = if (IsThumb(state.mThumbY, thumb)) .Y else if (IsThumb(state.mThumbX, thumb)) .X else return;

    //the drag is in the units the region is placed in, before its own scale
    const scale = if (region.GetComponent(TransformComponent)) |transform| transform.GetWorldScale() else Vec3(f32){ .x = 1, .y = 1, .z = 1 };
    const size = RegionSize(region) orelse return;
    const track = Get(size, axis);
    const content = Get(state.mContentSize, axis);
    const travel = track - ThumbLength(track, content);
    if (travel <= 0) return;
    //the thumb's whole travel is the whole scroll range
    const per_unit = (content - track) / travel;
    switch (axis) {
        //dragging the thumb down scrolls down, and down is -y
        .Y => try ScrollBy(engine_context, region, .{ .x = 0, .y = -drag.mDelta.y / scale.y * per_unit }),
        .X => try ScrollBy(engine_context, region, .{ .x = drag.mDelta.x / scale.x * per_unit, .y = 0 }),
    }
}

/// Once a frame, after layout and before world transforms: every scrolling region in `world` whose children run
/// past it gets a thumb along that edge, placed for how far it is scrolled, and one that no longer needs one loses it
pub fn Update(_: *ScrollSystem, engine_context: *EngineContext, world: *WorldManager) !void {
    const ui_manager = &engine_context.mUIManager;
    const element_ids = try ui_manager.GetGroup(engine_context.FrameAllocator(), .{ .Component = ScrollComponent });
    for (element_ids.items) |element_id| {
        const element = UIElement{ .mID = element_id, .mManager = ui_manager };
        const region = element.GetOwner();
        //an element no entity has taken yet has nothing to compare
        if (!region.IsIDValid() or region.mManager != world or !region.IsActive()) continue;
        const scroll = element.GetComponent(ScrollComponent).?.*;
        const state = element.GetComponent(ScrollStateComponent) orelse continue;
        const size = RegionSize(region) orelse Vec2(f32){ .x = 0, .y = 0 };
        try UpdateThumb(engine_context, region, scroll, state, &state.mThumbY, .Y, size);
        try UpdateThumb(engine_context, region, scroll, state, &state.mThumbX, .X, size);
    }
}

/// Moves a region's scroll offset by `delta` and asks for it to be laid out again, which keeps it in range
pub fn ScrollBy(engine_context: *EngineContext, region: Entity, delta: Vec2(f32)) !void {
    const state = UIManager.GetUIComponent(region, ScrollStateComponent) orelse return;
    state.mOffset = state.mOffset.AddVec(delta);
    try region.MarkLayoutDirty(engine_context);
}

/// `state` and `thumb_slot` (one of its thumbs) live in the UIManager's ECS, so making the thumb entity in the region's
/// world never moves them
fn UpdateThumb(engine_context: *EngineContext, region: Entity, scroll: ScrollComponent, state: *ScrollStateComponent, thumb_slot: *?Entity, axis: Layout.Axis, size: Vec2(f32)) !void {
    const track = Get(size, axis);
    const content = Get(state.mContentSize, axis);
    const overflows = scroll.mScroll.Along(axis) and content > track + 0.001 and track > 0;

    if (!overflows) {
        if (thumb_slot.*) |thumb| {
            if (thumb.IsActive()) {
                //deletes wait for the end of the frame, which is after this frame is drawn
                if (thumb.GetComponent(QuadComponent)) |quad| quad.mShouldRender = false;
                try thumb.Delete(engine_context);
            }
        }
        thumb_slot.* = null;
        return;
    }

    const thumb = try ThumbEntity(engine_context, region, thumb_slot);
    const length = ThumbLength(track, content);
    const scrolled = Get(state.mOffset, axis);
    //how far along its travel, from the start (the top, or the left)
    const along = (track - length) * std.math.clamp(scrolled / (content - track), 0, 1);

    const quad = thumb.GetComponent(QuadComponent).?;
    quad.mShouldRender = true;
    const radius = THUMB_THICKNESS / 2;
    quad.mCornerRadii = .{ .x = radius, .y = radius, .z = radius, .w = radius };
    const translation: Vec3(f32) = switch (axis) {
        //down the right edge
        .Y => blk: {
            quad.mSize = .{ .x = THUMB_THICKNESS, .y = length };
            break :blk .{ .x = size.x / 2 - THUMB_THICKNESS / 2, .y = size.y / 2 - length / 2 - along, .z = THUMB_DEPTH };
        },
        //along the bottom edge
        .X => blk: {
            quad.mSize = .{ .x = length, .y = THUMB_THICKNESS };
            break :blk .{ .x = -size.x / 2 + length / 2 + along, .y = -size.y / 2 + THUMB_THICKNESS / 2, .z = THUMB_DEPTH };
        },
    };

    const current = thumb.GetComponent(TransformComponent).?.GetTranslation();
    if (current.x != translation.x or current.y != translation.y or current.z != translation.z) {
        try thumb.SetTranslation(engine_context, translation);
    }
}

/// The thumb's quad, made the first time its region overflows
fn ThumbEntity(engine_context: *EngineContext, region: Entity, thumb_slot: *?Entity) !Entity {
    if (thumb_slot.*) |thumb| {
        if (thumb.IsActive()) return thumb;
    }
    const thumb = try region.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
    if (thumb.GetComponent(NameComponent)) |name| {
        name.mName.clearRetainingCapacity();
        try name.mName.appendSlice(engine_context.EngineAllocator(), "Scrollbar");
    }
    _ = try thumb.AddComponent(engine_context, QuadComponent{});
    //its colors, including when it is hovered and dragged, are the theme's
    try UIManager.Style(engine_context, thumb, "Scrollbar");
    thumb_slot.* = thumb;
    return thumb;
}

/// As long as the part of the content in view is of all of it, along a track of `track`
fn ThumbLength(track: f32, content: f32) f32 {
    if (content <= 0) return track;
    return std.math.clamp(track * track / content, @min(THUMB_MIN_LENGTH, track), track);
}

/// The nearest region in `chain` (what the pointer is over, then each thing it is inside) that scrolls along `axis`
fn NearestScrolling(chain: []const Entity, axis: Layout.Axis) ?Entity {
    for (chain) |entity| {
        if (!entity.IsActive()) continue;
        const scroll = UIManager.GetUIComponent(entity, ScrollComponent) orelse continue;
        if (scroll.mScroll.Along(axis)) return entity;
    }
    return null;
}

/// The region's size in its own units: what layout gave it, or its quad's
fn RegionSize(region: Entity) ?Vec2(f32) {
    if (region.GetComponent(LayoutItemComponent)) |item| return item.mComputedSize;
    if (region.GetComponent(QuadComponent)) |quad| return quad.mSize;
    return null;
}

fn Step(region: Entity) f32 {
    return UIManager.GetUIComponent(region, ScrollComponent).?.mWheelStep;
}

fn Parent(entity: Entity) ?Entity {
    const child_component = entity.GetComponent(EntityChildComponent) orelse return null;
    return Entity{ .mID = child_component.mParent, .mManager = entity.mManager };
}

fn IsThumb(slot: ?Entity, entity: Entity) bool {
    const thumb = slot orelse return false;
    return thumb.mID == entity.mID;
}

fn Get(v: Vec2(f32), axis: Layout.Axis) f32 {
    return switch (axis) {
        .X => v.x,
        .Y => v.y,
    };
}

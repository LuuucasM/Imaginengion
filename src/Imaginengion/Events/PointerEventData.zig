//! What the pointer (the mouse) does to entities: moments, where HoveredTag, PressedTag and DropHoverTag are the states
//! that last. Not just for UI: anything a ray can hit can be hovered, clicked, dragged or dropped on. Each event is for
//! one entity, `mEntity`, kept beside the event rather than in it: only that entity's scripts are handed the event
//! (PointerEvent), so a script never has to check it is the one meant. The entity under the pointer and everything it
//! is inside (its parent, and so on up) each get their own, so a button hears about a click that landed on its label:
//! `mTarget` is the entity that was actually under the pointer. See Pointer/PointerSystem.zig, which sends them.
const Entity = @import("../ECSObjects/Entity.zig");
const MouseCodes = @import("../Inputs/InputEnums.zig").MouseCodes;
const Vec3 = @import("../Math/MathTypes.zig").Vec3;

pub const EventCategories = enum {
    /// processed once a frame, after the input events that cause them and before game logic
    Pointer,
};

pub const EventT = EntityEvent;

/// One pointer event and the one entity it is sent to
pub const EntityEvent = struct {
    mEntity: Entity,
    mEvent: PointerEvent,
};

/// What happened, as the entity's OnPointerEventScripts are handed it
pub const PointerEvent = union(enum) {
    PointerEnter: PointerEnterEvent,
    PointerExit: PointerExitEvent,
    PointerPressed: PointerButtonEvent,
    PointerReleased: PointerButtonEvent,
    PointerClicked: PointerClickedEvent,
    PointerDragStart: PointerDragStartEvent,
    PointerDrag: PointerDragEvent,
    PointerDragEnd: PointerDragEndEvent,
    PointerDropped: PointerDroppedEvent,
};

/// The pointer is now over the entity or something inside it, and wasn't before
pub const PointerEnterEvent = struct {};

/// The pointer is no longer over the entity or anything inside it
pub const PointerExitEvent = struct {};

/// A mouse button went down over the entity, or came back up. The release goes to whatever was pressed, even if
/// the pointer has left it since
pub const PointerButtonEvent = struct {
    mButton: MouseCodes,
    /// where the pointer's ray met the target, in the world
    mPosition: Vec3(f32),
    mTarget: Entity,
};

/// A button was pressed and released in place (the input manager's click) over the entity: it was under the pointer
/// both when the button went down and when it came up
pub const PointerClickedEvent = struct {
    mButton: MouseCodes,
    /// 1 for a single click, 2 for a double click, and so on
    mClicks: u8,
    mPosition: Vec3(f32),
    mTarget: Entity,
};

/// A held button has moved far enough from where it went down that it is a drag rather than a click. Everything
/// about a drag goes to what the button went down on, wherever the pointer has got to since
pub const PointerDragStartEvent = struct {
    mButton: MouseCodes,
    mTarget: Entity,
};

/// The pointer moved during a drag. The movement is in the units the grabbed entity (mTarget) is placed in, so
/// something dragged can add mDelta to its translation and stay under the pointer: canvas units for an overlay
/// entity, and for a world entity world units across the plane facing the camera through where it was grabbed
pub const PointerDragEvent = struct {
    mButton: MouseCodes,
    /// since the last drag event
    mDelta: Vec3(f32),
    /// since the button went down
    mTotal: Vec3(f32),
    mTarget: Entity,
};

/// The button came up. Sent just before its PointerReleased
pub const PointerDragEndEvent = struct {
    mButton: MouseCodes,
    mTotal: Vec3(f32),
    mTarget: Entity,
};

/// A drag source (DragSourceComponent) was let go over a drop target (DropTargetComponent) that takes it. Sent to
/// the target only: the nearest one taking the source, going up from what was under the pointer. The target reads
/// what it needs from the source's components
pub const PointerDroppedEvent = struct {
    mSource: Entity,
    /// where the pointer's ray met what it was over, in the world
    mPosition: Vec3(f32),
};

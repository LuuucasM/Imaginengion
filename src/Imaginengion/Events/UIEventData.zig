//! What the pointer (the mouse) does to entities: moments, where HoveredTag and PressedTag are the states that
//! last. Each event is for one entity, `mEntity`. The entity under the pointer and everything it is inside (its
//! parent, and so on up) each get their own, so a button hears about a click that landed on its label: `mTarget`
//! is the entity that was actually under the pointer. See UI/PointerSystem.zig, which sends them.
const Entity = @import("../ECSObjects/Entity.zig");
const MouseCodes = @import("../Inputs/InputEnums.zig").MouseCodes;
const Vec3 = @import("../Math/MathTypes.zig").Vec3;

pub const EventCategories = enum {
    /// processed once a frame, after the input events that cause them and before game logic
    Pointer,
};

pub const EventT = union(enum) {
    Default: DefaultEvent,
    PointerEnter: PointerEnterEvent,
    PointerExit: PointerExitEvent,
    PointerPressed: PointerButtonEvent,
    PointerReleased: PointerButtonEvent,
    PointerClicked: PointerClickedEvent,
};

pub const DefaultEvent = struct {};

/// The pointer is now over the entity or something inside it, and wasn't before
pub const PointerEnterEvent = struct {
    mEntity: Entity,
};

/// The pointer is no longer over the entity or anything inside it
pub const PointerExitEvent = struct {
    mEntity: Entity,
};

/// A mouse button went down over the entity, or came back up. The release goes to whatever was pressed, even if
/// the pointer has left it since
pub const PointerButtonEvent = struct {
    mEntity: Entity,
    mButton: MouseCodes,
    /// where the pointer's ray met the target, in the world
    mPosition: Vec3(f32),
    mTarget: Entity,
};

/// A button was pressed and released in place (the input manager's click) over the entity: it was under the pointer
/// both when the button went down and when it came up
pub const PointerClickedEvent = struct {
    mEntity: Entity,
    mButton: MouseCodes,
    /// 1 for a single click, 2 for a double click, and so on
    mClicks: u8,
    mPosition: Vec3(f32),
    mTarget: Entity,
};

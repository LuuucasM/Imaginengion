//! What the UI does: a text input getting the keyboard and being typed into, popups opening and closing. Moments, where
//! FocusedTag is the state that lasts. Each event is for one entity, `mEntity`, kept beside the event rather than in it:
//! only that entity's scripts are handed the event (UIEvent), so a script never has to check it is the one meant. The
//! entity it happened to and everything it is inside (its parent, and so on up) each get their own, and `mTarget` is
//! the entity it actually happened to. See UI/FocusSystem.zig and UI/PopupSystem.zig, which send them. What the pointer does is its own,
//! Events/PointerEventData.zig, since anything can be pointed at, not just UI.
const Entity = @import("../ECSObjects/Entity.zig");
const UIElement = @import("../ECSObjects/UIElement.zig");

/// The UIManager's event manager's events
pub const EventCategories = enum {
    /// processed once a frame, after the pointer's events and before game logic
    UI,
    /// the UIManager's own: elements deleted at the end of the frame
    EndOfFrame,
};

pub const EventT = union(enum) {
    Default: DefaultEvent,
    DestroyUIElement: DestroyUIElementEvent,
    /// what the UI did, for one entity: the UI category's events
    Entity: EntityEvent,
};

/// One UI event and the one entity it is sent to
pub const EntityEvent = struct {
    mEntity: Entity,
    mEvent: UIEvent,
};

/// What happened, as the entity's OnUIEventScripts are handed it
pub const UIEvent = union(enum) {
    FocusGained: FocusEvent,
    FocusLost: FocusEvent,
    TextChanged: TextEvent,
    TextSubmitted: TextEvent,
    PopupOpened: PopupEvent,
    PopupClosed: PopupEvent,
    ValueChanged: ValueEvent,
};

pub const DefaultEvent = struct {};

pub const DestroyUIElementEvent = struct {
    Element: UIElement,
};

/// A text input (TextInputComponent) got the keyboard, or lost it. Losing it comes after the TextSubmitted or the
/// revert's TextChanged that ended the edit
pub const FocusEvent = struct {
    /// the text input itself
    mTarget: Entity,
};

/// For a text input (mTarget), read its TextComponent for the text:
///   - TextChanged: its text was edited: typed into, deleted from, pasted into, or put back by Escape
///   - TextSubmitted: the edit was kept, by Enter or by pressing somewhere else. Sent even if the text is the same
///     as before the edit, so compare against what you had if that matters
pub const TextEvent = struct {
    mTarget: Entity,
};

/// A popup (mTarget, the root with the PopupComponent) was opened or closed. Closing one closes the popups opened on
/// top of it as well, each with its own PopupClosed, the top one first
pub const PopupEvent = struct {
    mTarget: Entity,
    /// what it was opened against, null for a point (a right-click menu)
    mOpener: ?Entity,
};

/// A widget's value changed (mTarget): a checkbox checked or unchecked, a row of a list selected. Sent by whatever
/// changed it, e.g. the stock widget scripts (UI/WidgetActions.zig). Read the value off mTarget, e.g. its SelectedTag
pub const ValueEvent = struct {
    mTarget: Entity,
};

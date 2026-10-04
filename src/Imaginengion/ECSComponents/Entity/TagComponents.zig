const EngineContext = @import("../../Core/EngineContext.zig");

//The three body types. A rigid body carries exactly one, and the tag is the record of its type: it is saved,
//and changing the type is swapping the tag (adding one takes the others off, see Entity.OnBodyTypeTagAdded).
//The tags are also the queries: integration visits only dynamic and kinematic bodies, and the broad pass
//pairs by type.

/// Never moves: floors, walls. Can't be pushed and is never integrated, whatever velocity it is given
pub const StaticBodyTag = struct {
    pub const Editable: bool = false;
    pub const Name: []const u8 = "StaticBodyTag";

    pub fn Deinit(_: *StaticBodyTag, _: *EngineContext) void {}
};

/// Moved by code, through its velocity alone: paddles, moving platforms, doors. No gravity or forces, and
/// can't be pushed, but pushes dynamic bodies out of its way
pub const KinematicBodyTag = struct {
    pub const Editable: bool = false;
    pub const Name: []const u8 = "KinematicBodyTag";

    pub fn Deinit(_: *KinematicBodyTag, _: *EngineContext) void {}
};

/// Moved by physics: gravity, forces and collisions
pub const DynamicBodyTag = struct {
    pub const Editable: bool = false;
    pub const Name: []const u8 = "DynamicBodyTag";

    pub fn Deinit(_: *DynamicBodyTag, _: *EngineContext) void {}
};

/// Marks an entity whose layout needs working out again: something it or its tree is sized or placed by has
/// changed. The tag is the query: the layout pass only visits the trees that have one, and clears it.
/// It carries no data, so the sparse set stores no value array for it. Never saved: a loaded tree is laid out
/// when it is first seen
pub const LayoutDirtyTag = struct {
    pub const Editable: bool = false;
    pub const Name: []const u8 = "LayoutDirtyTag";

    pub fn Deinit(_: *LayoutDirtyTag, _: *EngineContext) void {}
};

/// Marks an entity folded away by a collapsed layout item: the item itself and everything under it. The tag is the
/// query: the renderer and picking leave tagged entities out (ShapeGeometry.GatherViewShapes), so they are neither
/// drawn nor clickable, and only the layout pass puts it on or takes it off. Never saved: a loaded tree works it
/// out again when it is laid out
pub const LayoutHiddenTag = struct {
    pub const Editable: bool = false;
    pub const Name: []const u8 = "LayoutHiddenTag";

    pub fn Deinit(_: *LayoutHiddenTag, _: *EngineContext) void {}
};

/// On an entity while the pointer is over it or over something inside it (see Pointer/PointerSystem.zig). A state to
/// check or query, e.g. for a hover color; the moment it starts and ends are PointerEnter and PointerExit events.
/// Never saved
pub const HoveredTag = struct {
    pub const Editable: bool = false;
    pub const Name: []const u8 = "HoveredTag";

    pub fn Deinit(_: *HoveredTag, _: *EngineContext) void {}
};

/// On an entity while a mouse button that went down on it (or on something inside it) is still held, even once the
/// pointer has moved off it. For a pushed in look, and for knowing what is being held or dragged. Never saved
pub const PressedTag = struct {
    pub const Editable: bool = false;
    pub const Name: []const u8 = "PressedTag";

    pub fn Deinit(_: *PressedTag, _: *EngineContext) void {}
};

/// On the one entity that has the keyboard: a text input (TextInputComponent) being typed into. For a "being edited"
/// look. Never saved
pub const FocusedTag = struct {
    pub const Editable: bool = false;
    pub const Name: []const u8 = "FocusedTag";

    pub fn Deinit(_: *FocusedTag, _: *EngineContext) void {}
};

/// On an entity that is selected: the selected row of a list, a selected unit, the open tab. What selects it is up to
/// whoever uses it, nothing sets it on its own. A state to check or query, e.g. for a selected color (the theme's
/// Selected). Never saved
pub const SelectedTag = struct {
    pub const Editable: bool = false;
    pub const Name: []const u8 = "SelectedTag";

    pub fn Deinit(_: *SelectedTag, _: *EngineContext) void {}
};

/// On an entity that can't be used right now, along with everything inside it: a greyed out menu item or button, a
/// locked door. The pointer passes it by (Pointer/PointerSystem.zig): it and what is inside it are never hovered,
/// pressed, clicked, dragged or dropped on, and the pointer counts as over whatever it is inside instead, which still
/// hears all of that. Its text inputs can't be typed into, and styles show the theme's Disabled colors for it and
/// everything inside it. Saved, so a template can start out disabled
pub const DisabledTag = struct {
    pub const Editable: bool = false;
    pub const Name: []const u8 = "DisabledTag";

    pub fn Deinit(_: *DisabledTag, _: *EngineContext) void {}
};

/// On a drop target (DropTargetComponent) while a drag source it takes is held over it: for a "drop here" look. The
/// moment the source is let go there is the PointerDropped event. Never saved
pub const DropHoverTag = struct {
    pub const Editable: bool = false;
    pub const Name: []const u8 = "DropHoverTag";

    pub fn Deinit(_: *DropHoverTag, _: *EngineContext) void {}
};

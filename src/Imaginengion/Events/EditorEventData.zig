//! What the editor's panels ask the editor itself to do, handled at the end of the frame (EditorProgram.OnEditorEvent):
//! things that need the editor's own state, like the selection, or the content browser's folder to save into.
const SelectedObject = @import("../Programs/EditorProgram.zig").SelectedObject;
const AssetHandle = @import("../ECSObjects/AssetHandle.zig");

pub const EventCategories = enum {
    EndOfFrame,
};

pub const EventT = union(enum) {
    DefaultEvent: DefaultEvent,
    SelectObjectEvent: SelectObjectEvent,
    MakeTmplEvent: MakeTmplEvent,
    OpenTmplEvent: OpenTmplEvent,
};

pub const DefaultEvent = struct {};

/// The editor's selection becomes this object, or nothing, e.g. from a click in a viewport
pub const SelectObjectEvent = struct {
    mObject: ?SelectedObject,
};

/// Make Template from the hierarchy's right click menu. Handled by the editor since it saves into the content
/// browser's current folder
pub const MakeTmplEvent = struct {
    mObject: SelectedObject,
};

/// Opens a template in its own edit window (see TmplEditPanel), or brings its window forward if it is already open.
/// Carries a reference of its own on the handle, which the editor takes over or releases
pub const OpenTmplEvent = struct {
    mTmpl: AssetHandle,
};

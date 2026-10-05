const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Inspector = @import("../../UI/Inspector.zig");

const FieldBindingComponent = @This();

pub const Editable: bool = false;
pub const Name: []const u8 = "FieldBindingComponent";

/// On a widget's UI element: the field of an object's component the widget shows and edits (made by Inspector.Builder).
/// The binding system (UI/BindingSystem.zig) puts the field's value on the widget every frame it isn't being edited,
/// and writes the widget's value into the field when it is. The field is found again each time from the object, the
/// component and where the field is inside it, since components move in memory. Never saved: the inspector that made it
/// is built again from the object
/// The object the component is on
mObject: Inspector.ObjectRef,
/// Finds the object's component again, null once either has gone
mResolve: *const fn (Inspector.ObjectRef) ?*anyopaque,
/// Where the field is inside the component, in bytes
mOffset: usize,
/// How the field's type is read and written
mAccess: *const Inspector.Access,
/// What has to happen after the component is edited (dirty tags and the like)
mAfterEdit: *const fn (*EngineContext, Inspector.ObjectRef) anyerror!void,
/// The field's own, after it is edited
mOnChange: ?Inspector.OnChange = null,
/// How a number is shown, if not as it is kept
mConvert: ?Inspector.Conversion = null,
/// The inspector to build again when this field is edited, null if it doesn't change what is shown
mRebuild: ?Entity = null,

pub fn Deinit(_: *FieldBindingComponent, _: *EngineContext) void {}

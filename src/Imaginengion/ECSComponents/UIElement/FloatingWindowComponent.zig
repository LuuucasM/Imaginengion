const EngineContext = @import("../../Core/EngineContext.zig");
const FloatingWindowComponent = @This();

pub const Editable: bool = false;
pub const Name: []const u8 = "FloatingWindowComponent";

/// On an entity's UI element (UIElementComponent): the entity is the root of a floating window (Widgets.FloatingWindow),
/// one of the windows of its scene that can be moved about and brought in front of the others. Raising one puts it in
/// front of every other floating window in its scene (WidgetActions.RaiseWindow), and closing one inside it finds it.
/// Carries no data

pub fn Deinit(_: *FloatingWindowComponent, _: *EngineContext) void {}

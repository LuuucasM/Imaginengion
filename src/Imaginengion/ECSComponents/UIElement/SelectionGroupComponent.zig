const EngineContext = @import("../../Core/EngineContext.zig");
const SelectionGroupComponent = @This();

pub const Editable: bool = false;
pub const Name: []const u8 = "SelectionGroupComponent";

/// On an entity's UI element (UIElementComponent): only one entity in its whole tree is selected at a time, as far as
/// selecting goes (WidgetActions.Select): a tree's rows, where a row and one in another branch aren't siblings, or a list
/// whose rows sit inside containers. Without one, selecting only unselects an entity's siblings. Selecting takes
/// SelectedTag off everything else in its tree, checked checkboxes included, so it goes on the list or tree itself rather
/// than on a whole panel. Carries no data

pub fn Deinit(_: *SelectionGroupComponent, _: *EngineContext) void {}

const EngineContext = @import("../../Core/EngineContext.zig");
const DragSourceComponent = @This();

pub const Editable: bool = false;
pub const Name: []const u8 = "DragSourceComponent";

/// Makes an entity something that can be dragged onto a drop target (DropTargetComponent). It carries no data of
/// its own: what it carries is its other components, which is what a target checks and reads from on the drop.
/// Pressing on it or on anything inside it and dragging (left button) picks it up. Set up by code, never saved

pub fn Deinit(_: *DragSourceComponent, _: *EngineContext) void {}

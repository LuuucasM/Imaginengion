const EngineContext = @import("../../Core/EngineContext.zig");

const StyleDirtyTag = @This();

pub const Editable: bool = false;
pub const Name: []const u8 = "StyleDirtyTag";

/// Marks an element whose entity has to take its style again: its state changed (hovered, pressed, focused, selected,
/// disabled, or anything it is inside disabled), it was given another style, or a part the style colors (its shape,
/// surface or text) was added. The tag is the query: the style system only restyles the elements that have one, and
/// clears it. It carries no data. Never saved or copied: an element that is loaded or copied is marked when its
/// entity takes it (UIManager.Adopt). See UIManager.MarkStyleDirty
pub fn Deinit(_: *StyleDirtyTag, _: *EngineContext) void {}

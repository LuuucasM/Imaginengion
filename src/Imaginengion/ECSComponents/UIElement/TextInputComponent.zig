const EngineContext = @import("../../Core/EngineContext.zig");
const TextInputComponent = @This();

pub const Editable: bool = false;
pub const Name: []const u8 = "TextInputComponent";

/// On an entity's UI element (UIElementComponent): makes the entity's TextComponent something the player can type into.
/// Pressing on it (left button) gives it the keyboard: the entity gets FocusedTag and a caret, and typing edits its text
/// until Enter, Escape or a press somewhere else. All of that is the focus system's (UI/FocusSystem.zig), so this
/// carries no data of its own

pub fn Deinit(_: *TextInputComponent, _: *EngineContext) void {}

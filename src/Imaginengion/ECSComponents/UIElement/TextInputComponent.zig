const EngineContext = @import("../../Core/EngineContext.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const Inspector = @import("../../UI/Inspector.zig");
const TextInputComponent = @This();

pub const Editable: bool = true;
pub const Name: []const u8 = "TextInputComponent";

/// On an entity's UI element (UIElementComponent): makes the entity's TextComponent something the player can type into.
/// Pressing on it (left button) gives it the keyboard: the entity gets FocusedTag and a caret, and typing edits its text
/// until Enter, Escape or a press somewhere else. All of that is the focus system's (UI/FocusSystem.zig)
/// What gives it the keyboard
mFocusOn: FocusOn = .Press,

pub const FocusOn = enum {
    /// the left button going down on it: a text box
    Press,
    /// a double click on it, so a single press and a drag are left for something else: a number field's value, which
    /// dragging changes, or a list row's name
    DoubleClick,
};

pub fn Deinit(_: *TextInputComponent, _: *EngineContext) void {}

pub fn UIRender(self: *TextInputComponent, ui: *Inspector.Builder) !void {
    try ui.Enum(FocusOn, &self.mFocusOn, "Focus On", .{});
}

const Json = JsonUtils.JsonFields(TextInputComponent, .{
    .FocusOn = "mFocusOn",
});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

const std = @import("std");
const EngineContext = @import("../../Core/EngineContext.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const Inspector = @import("../../UI/Inspector.zig");

const NumberFieldComponent = @This();

pub const Editable: bool = true;
pub const Name: []const u8 = "NumberFieldComponent";

/// On an entity's UI element (UIElementComponent): makes the entity a field showing the number in its AttribComponent,
/// which dragging sideways (left button) changes and a double click lets the player type. Its text is a TextComponent on
/// the entity itself or on its first child that has one, kept showing the value; for typing, that entity needs a
/// TextInputComponent focusing on a double click. All of that is the number field system's (UI/NumberFieldSystem.zig),
/// and every change sends ValueChanged to the entity and everything it is inside.
/// How much the value changes per unit dragged (canvas units in an overlay)
mSpeed: f32 = 0.1,
/// The lowest it goes, by dragging or typing. Null for no limit
mMin: ?f32 = null,
/// The highest it goes. Null for no limit
mMax: ?f32 = null,
/// How many decimal places a float is shown with. Whole number values show none
mDecimals: u8 = 3,

pub fn Deinit(_: *NumberFieldComponent, _: *EngineContext) void {}

/// `value` kept within the limits
pub fn Clamp(self: NumberFieldComponent, value: f64) f64 {
    var clamped = value;
    if (self.mMin) |min| clamped = @max(clamped, min);
    if (self.mMax) |max| clamped = @min(clamped, max);
    return clamped;
}

pub fn UIRender(self: *NumberFieldComponent, ui: *Inspector.Builder) !void {
    try ui.Float(&self.mSpeed, "Speed", .{ .Speed = 0.01, .Min = 0 });
    try ui.OptionalFloat(&self.mMin, "Min", .{});
    try ui.OptionalFloat(&self.mMax, "Max", .{});
    try ui.UInt8(&self.mDecimals, "Decimals", .{ .Speed = 0.1, .Min = 0, .Max = 9, .Decimals = 0 });
}

const Json = JsonUtils.JsonFields(NumberFieldComponent, .{
    .Speed = "mSpeed",
    .Min = "mMin",
    .Max = "mMax",
    .Decimals = "mDecimals",
});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

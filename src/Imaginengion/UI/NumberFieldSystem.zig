//! Number fields: entities whose UI element has a NumberFieldComponent, showing the number in their AttribComponent.
//! Part of the UIManager.
//!   - dragging one sideways (left button) changes its value by the field's speed per unit dragged. A float changes
//!     smoothly; a whole number changes in steps, with what is left over kept for the rest of the drag, so a slow drag
//!     still gets there. The field's limits hold, and a u32 never goes below 0. A float with a lowest value and no
//!     highest is a size (a width, a gap, a font size): it moves by a share of itself instead, so a small size moves
//!     in small steps and a big one in big ones. Holding Shift drags ten times slower
//!   - typing into its text (a double click, see TextInputComponent) and keeping the edit sets the value to the number
//!     typed, within the limits. Anything that isn't a number puts the value's text back
//!   - its text shows its value every frame it isn't being typed into, so code can just set the AttribComponent
//!   - every change of value sends ValueChanged to the field and everything it is inside
const std = @import("std");
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const UIElement = @import("../ECSObjects/UIElement.zig");
const PointerEvent = @import("../Events/PointerEventData.zig").EventT;
const UIEvent = @import("../Events/UIEventData.zig").EventT;
const UIManager = @import("UIManager.zig");

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const AttribComponent = EntityComponents.AttribComponent;
const TextComponent = EntityComponents.TextComponent;
const NumberFieldComponent = @import("../ECSComponents/UIComponents.zig").NumberFieldComponent;

/// How much of itself a size moves per unit dragged
const SIZE_SHARE: f64 = 0.01;
/// The least a size moves per unit dragged, as a share of its field's speed: so it can still be dragged up from 0
const SIZE_LEAST_SHARE: f64 = 0.02;
/// How much slower a drag with Shift held is
const FINE_FACTOR: f64 = 0.1;

const NumberFieldSystem = @This();
/// The entity showing a field's value
const LabelOf = UIManager.LabelOf;

pub const empty: NumberFieldSystem = .{};

/// The field being dragged
mDragged: ?Entity = null,
/// What the drag has moved its value by that it couldn't show yet: under a whole step, for a whole number
mRemainder: f64 = 0,

/// A frame's pointer events: a field being dragged changes its value
pub fn OnPointerEvent(self: *NumberFieldSystem, engine_context: *EngineContext, event: PointerEvent) !void {
    const zone = Tracy.ZoneInit("NumberFieldSystem::OnPointerEvent", @src());
    defer zone.Deinit();
    switch (event) {
        .PointerDragStart => |e| if (e.mButton == .BUTTON_LEFT and IsField(e.mEntity)) {
            self.mDragged = e.mEntity;
            self.mRemainder = 0;
        },
        .PointerDrag => |e| if (e.mButton == .BUTTON_LEFT and IsField(e.mEntity)) {
            if (self.mDragged == null or !Same(self.mDragged.?, e.mEntity)) {
                self.mDragged = e.mEntity;
                self.mRemainder = 0;
            }
            try self.Drag(engine_context, e.mEntity, e.mDelta.x);
        },
        .PointerDragEnd => |e| if (self.mDragged != null and Same(self.mDragged.?, e.mEntity)) {
            self.mDragged = null;
        },
        else => {},
    }
}

/// A frame's UI events: an edit kept in a field's text sets its value
pub fn OnUIEvent(_: *NumberFieldSystem, engine_context: *EngineContext, event: UIEvent) !void {
    const zone = Tracy.ZoneInit("NumberFieldSystem::OnUIEvent", @src());
    defer zone.Deinit();
    const submitted = switch (event) {
        .TextSubmitted => |e| e,
        else => return,
    };
    //one event per entity in the chain: the field's own
    const field = submitted.mEntity;
    if (!IsField(field) or !field.IsActive()) return;
    const label = LabelOf(field) orelse return;
    if (!Same(label, submitted.mTarget)) return;

    const typed = std.mem.trim(u8, label.GetComponent(TextComponent).?.mText.items, " \t");
    if (ParseNumber(typed)) |number| {
        try SetValue(engine_context, field, number);
    }
    //either way the text goes back to showing the value: formatted, or back from what wasn't a number
    try ShowValue(engine_context, field, label);
}

/// Once a frame, before layout (the text's size can change): every field not being typed into shows its value
pub fn Update(_: *NumberFieldSystem, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("NumberFieldSystem::Update", @src());
    defer zone.Deinit();
    const ui_manager = &engine_context.mUIManager;
    const focused = ui_manager.mFocusSystem.Focused();
    const element_ids = try ui_manager.GetGroup(engine_context.FrameAllocator(), .{ .Component = NumberFieldComponent });
    for (element_ids.items) |element_id| {
        const element = UIElement{ .mID = element_id, .mManager = ui_manager };
        const field = element.GetOwner();
        //an element no entity has taken yet has nothing to show
        if (!field.IsIDValid() or !field.IsActive()) continue;
        const label = LabelOf(field) orelse continue;
        if (focused != null and Same(focused.?, label)) continue;
        try ShowValue(engine_context, field, label);
    }
}

/// Moves a field's value by `units` dragged, keeping what a whole number can't show yet
fn Drag(self: *NumberFieldSystem, engine_context: *EngineContext, field: Entity, units: f32) !void {
    if (units == 0) return;
    //a field being typed into keeps its value until the edit ends
    if (engine_context.mUIManager.mFocusSystem.Focused()) |focused| {
        if (LabelOf(field)) |label| {
            if (Same(focused, label)) return;
        }
    }
    const settings = UIManager.GetUIComponent(field, NumberFieldComponent).?.*;
    const attrib = field.GetComponent(AttribComponent) orelse return;
    if (attrib.mData == .bool) return;

    const input = &engine_context.mInputManager;
    const fine = input.IsKeyPressed(.LSHIFT) or input.IsKeyPressed(.RSHIFT);
    const step = StepOf(settings, attrib.mData) * if (fine) FINE_FACTOR else 1;
    const wanted = settings.Clamp(attrib.mData.AsFloat() + self.mRemainder + @as(f64, units) * step);
    try SetValue(engine_context, field, wanted);
    //only what rounding to a whole number left: what a type's own floor cut off (a u32 at 0) isn't owed back
    self.mRemainder = std.math.clamp(wanted - attrib.mData.AsFloat(), -0.5, 0.5);
}

/// How much a field's value moves per unit dragged: its speed, or for a size (a float with a lowest value and no
/// highest) a share of itself, never less than a share of its speed
fn StepOf(settings: NumberFieldComponent, value: AttribComponent.ValueTypes) f64 {
    const speed: f64 = settings.mSpeed;
    const is_size = value == .float32 and settings.mMin != null and settings.mMax == null;
    if (!is_size) return speed;
    return @max(@abs(value.AsFloat()) * SIZE_SHARE, speed * SIZE_LEAST_SHARE);
}

/// Sets a field's value to `number` within its limits, and sends ValueChanged if that changed it
pub fn SetValue(engine_context: *EngineContext, field: Entity, number: f64) !void {
    const attrib = field.GetComponent(AttribComponent) orelse return;
    const settings = UIManager.GetUIComponent(field, NumberFieldComponent) orelse return;
    const before = attrib.mData;
    attrib.mData.SetFromFloat(settings.Clamp(number));
    if (!std.meta.eql(before, attrib.mData)) try engine_context.mUIManager.SendToChain(engine_context, field, .ValueChanged);
}

/// How a value is shown: a float with the field's decimals, the whole numbers as they are
pub fn Format(buffer: []u8, value: AttribComponent.ValueTypes, decimals: u8) []const u8 {
    return switch (value) {
        .float32 => |v| std.fmt.bufPrint(buffer, "{[v]d:.[p]}", .{ .v = if (v == 0) 0 else v, .p = decimals }),
        .uint32 => |v| std.fmt.bufPrint(buffer, "{d}", .{v}),
        .int32 => |v| std.fmt.bufPrint(buffer, "{d}", .{v}),
        .bool => |v| std.fmt.bufPrint(buffer, "{s}", .{if (v) "true" else "false"}),
    } catch buffer[0..0];
}

/// The number in typed text, null if it isn't one. true and false count, as 1 and 0
fn ParseNumber(typed: []const u8) ?f64 {
    if (std.ascii.eqlIgnoreCase(typed, "true")) return 1;
    if (std.ascii.eqlIgnoreCase(typed, "false")) return 0;
    const number = std.fmt.parseFloat(f64, typed) catch return null;
    return if (std.math.isFinite(number)) number else null;
}

/// Puts a field's value in its text, if the text doesn't show it already
fn ShowValue(engine_context: *EngineContext, field: Entity, label: Entity) !void {
    const attrib = field.GetComponent(AttribComponent) orelse return;
    const settings = UIManager.GetUIComponent(field, NumberFieldComponent) orelse return;
    var buffer: [64]u8 = undefined;
    const shown = Format(&buffer, attrib.mData, settings.mDecimals);
    const text = label.GetComponent(TextComponent).?;
    if (std.mem.eql(u8, text.mText.items, shown)) return;
    try text.SetText(engine_context, shown);
    //layout sizes text to fit
    try label.MarkLayoutDirty(engine_context);
}

fn IsField(entity: Entity) bool {
    return UIManager.HasUIComponent(entity, NumberFieldComponent);
}

fn Same(a: Entity, b: Entity) bool {
    return a.mID == b.mID and a.mManager == b.mManager;
}

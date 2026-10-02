//! Who has the keyboard: the one text input (TextInputComponent) being typed into, and the typing itself.
//!   - focus: the left button going down on a text input, or on anything inside one, gives it the keyboard. It gets
//!     FocusedTag and a blinking caret (a thin quad on a child entity, made and deleted here). Any button going down
//!     anywhere else takes the keyboard away again
//!   - typing: typed text (TextTyped events) goes in at the caret. Backspace, Delete, Left, Right, Home and End edit
//!     and move it, Ctrl+V pastes. Enter keeps the edit, Escape puts back the text it had when it got the keyboard,
//!     and either one ends it. A press somewhere else keeps the edit too
//!   - moments, as events through the engine's UI event manager (Events/UIEventData.zig), to the text input and
//!     everything it is inside: FocusGained, FocusLost, TextChanged and TextSubmitted
//!
//! Keys reach it at its scene's turn in the scene stack: whoever hands out key events runs the key scripts of the
//! scenes above its scene first (ScriptsProcessor.RunScriptAbove), then hands the key here if none of them took it,
//! and the scenes below never hear it. While it has the keyboard the input manager's IsKeyPressed reads false.
const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const MouseCodes = @import("../Inputs/InputEnums.zig").MouseCodes;
const KeyboardPressedEvent = @import("../Events/WindowEventData.zig").KeyboardPressedEvent;
const UIEvent = @import("../Events/UIEventData.zig").EventT;
const PointerSystem = @import("PointerSystem.zig");
const TextEdit = @import("TextEdit.zig");
const TextLayout = @import("../Renderer/TextLayout.zig");
const ShapeGeometry = @import("../Renderer/ShapeGeometry.zig");
const TextAsset = @import("../ECSComponents/AComponents.zig").TextAsset;
const MathTypes = @import("../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;
const Vec3 = MathTypes.Vec3;

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const TextInputComponent = EntityComponents.TextInputComponent;
const FocusedTag = EntityComponents.FocusedTag;
const TextComponent = EntityComponents.TextComponent;
const QuadComponent = EntityComponents.QuadComponent;
const NameComponent = EntityComponents.NameComponent;
const TransformComponent = EntityComponents.TransformComponent;
const EntitySceneComponent = EntityComponents.EntitySceneComponent;
const StackPosComponent = @import("../ECSComponents/SComponents.zig").StackPosComponent;

const FocusSystem = @This();

/// How long the caret stays on, and then off
const BLINK_SECONDS: f32 = 0.5;
/// The caret's width, as a share of the font size
const CARET_WIDTH: f32 = 0.08;
/// How far in front of the text the caret sits, so it is drawn over the letters
const CARET_DEPTH: f32 = 0.01;

/// How an edit ends
pub const EndHow = enum {
    /// keeps the text: TextSubmitted
    Submit,
    /// puts back the text it had when it got the keyboard: TextChanged if that is different
    Revert,
};

pub const empty: FocusSystem = .{};

/// The text input that has the keyboard
mFocused: ?Entity = null,
/// Where typing goes in its text: a byte index at the start of a codepoint, or the text's length
mCaret: usize = 0,
/// Its text when it got the keyboard, for Escape
mOriginal: std.ArrayList(u8) = .empty,
/// The caret's quad, a child of the focused text input
mCaretEntity: ?Entity = null,
/// Since the caret last moved or the text last changed: it shows straight away after either, then blinks
mBlinkTime: f32 = 0,

pub fn Deinit(self: *FocusSystem, engine_allocator: std.mem.Allocator) void {
    self.mOriginal.deinit(engine_allocator);
    self.* = .empty;
}

/// Forgets everything without touching an entity, for when the world they are in is about to be thrown away
pub fn Reset(self: *FocusSystem, engine_context: *EngineContext) void {
    self.mFocused = null;
    self.mCaretEntity = null;
    self.mCaret = 0;
    self.mOriginal.clearRetainingCapacity();
    ReleaseKeyboard(engine_context);
}

/// The text input that has the keyboard, null if none does
pub fn Focused(self: *const FocusSystem) ?Entity {
    const focused = self.mFocused orelse return null;
    return if (focused.IsActive()) focused else null;
}

/// Where the focused text input's scene sits in the scene stack, which is its turn at key events. Null if nothing
/// has the keyboard
pub fn FocusedStackPos(self: *const FocusSystem) ?usize {
    const focused = self.Focused() orelse return null;
    const scene = focused.GetComponent(EntitySceneComponent).?.mScene;
    const stack_pos = scene.GetComponent(StackPosComponent) orelse return 0;
    return stack_pos.mPosition;
}

/// The caret's position in the focused text, see mCaret
pub fn Caret(self: *const FocusSystem) usize {
    return self.mCaret;
}

/// A mouse button went down on what the pointer system has it over: call it after the pointer system's OnPressed.
/// The left button on a text input (or anything inside one) gives it the keyboard, with the caret where it went down.
/// Any button anywhere outside the focused text input ends its edit, keeping it
pub fn OnPressed(self: *FocusSystem, engine_context: *EngineContext, pointer: *const PointerSystem, button: MouseCodes) !void {
    var pressed: ?Entity = null;
    for (pointer.mHovered.items) |entity| {
        if (entity.IsActive() and entity.HasComponent(TextInputComponent)) {
            pressed = entity;
            break;
        }
    }

    if (self.Focused()) |focused| {
        if (pressed != null and Same(pressed.?, focused)) {
            if (button == .BUTTON_LEFT) try self.PlaceCaretAt(engine_context, focused, pointer.mInput);
            return;
        }
        try self.EndEdit(engine_context, .Submit);
    }

    if (button != .BUTTON_LEFT) return;
    const text_input = pressed orelse return;
    if (try self.Focus(engine_context, text_input)) try self.PlaceCaretAt(engine_context, text_input, pointer.mInput);
}

/// Gives `entity` the keyboard, with the caret at the end of its text. Returns false if it has no text to type into
pub fn Focus(self: *FocusSystem, engine_context: *EngineContext, entity: Entity) !bool {
    if (self.Focused()) |focused| {
        if (Same(focused, entity)) return true;
        try self.EndEdit(engine_context, .Submit);
    }
    const text = entity.GetComponent(TextComponent) orelse return false;

    self.mFocused = entity;
    self.mCaret = text.mText.items.len;
    self.mBlinkTime = 0;
    self.mOriginal.clearRetainingCapacity();
    try self.mOriginal.appendSlice(engine_context.EngineAllocator(), text.mText.items);

    if (!entity.HasComponent(FocusedTag)) _ = try entity.AddComponent(engine_context, FocusedTag{});
    engine_context.mInputManager.mKeyboardTaken = true;
    engine_context.mAppWindow.StartTextInput();
    try Send(engine_context, entity, .FocusGained);
    return true;
}

/// Ends the edit of the focused text input, if there is one, and takes the keyboard back
pub fn EndEdit(self: *FocusSystem, engine_context: *EngineContext, how: EndHow) !void {
    const focused = self.mFocused orelse return;
    self.mFocused = null;
    ReleaseKeyboard(engine_context);

    //deletes wait for the end of the frame, which is after this frame is drawn
    if (self.mCaretEntity) |caret| {
        if (caret.IsActive()) {
            if (caret.GetComponent(QuadComponent)) |quad| quad.mShouldRender = false;
            try caret.Delete(engine_context);
        }
    }
    self.mCaretEntity = null;

    if (!focused.IsActive()) return;
    switch (how) {
        .Submit => try Send(engine_context, focused, .TextSubmitted),
        .Revert => if (focused.GetComponent(TextComponent)) |text| {
            if (!std.mem.eql(u8, text.mText.items, self.mOriginal.items)) {
                try text.SetText(engine_context, self.mOriginal.items);
                try self.Changed(engine_context, focused);
            }
        },
    }
    if (focused.HasComponent(FocusedTag)) try focused.RemoveComponentSync(engine_context, FocusedTag);
    try Send(engine_context, focused, .FocusLost);
}

/// A key went down (or repeated, from being held) and it is the focused text input's turn at it
pub fn OnKeyPressed(self: *FocusSystem, engine_context: *EngineContext, e: KeyboardPressedEvent) !void {
    const focused = self.Focused() orelse return;
    const text = focused.GetComponent(TextComponent) orelse return;
    //code may have changed the text since
    self.mCaret = @min(self.mCaret, text.mText.items.len);
    self.mBlinkTime = 0;

    const input = &engine_context.mInputManager;
    const ctrl = input.IsKeyPressedUnfiltered(.LCTRL) or input.IsKeyPressedUnfiltered(.RCTRL);
    switch (e._InputCode) {
        .BACKSPACE, .KP_BACKSPACE => if (TextEdit.Backspace(&text.mText, &self.mCaret)) try self.Changed(engine_context, focused),
        .DELETE => if (TextEdit.Delete(&text.mText, self.mCaret)) try self.Changed(engine_context, focused),
        .LEFT => self.mCaret = TextEdit.PrevBoundary(text.mText.items, self.mCaret),
        .RIGHT => self.mCaret = TextEdit.NextBoundary(text.mText.items, self.mCaret),
        .HOME => self.mCaret = 0,
        .END => self.mCaret = text.mText.items.len,
        .RETURN, .RETURN2, .KP_ENTER => try self.EndEdit(engine_context, .Submit),
        .ESCAPE => try self.EndEdit(engine_context, .Revert),
        .V => if (ctrl) {
            const clipboard = try engine_context.mAppWindow.GetClipboardText(engine_context.FrameAllocator());
            try self.Type(engine_context, clipboard);
        },
        else => {},
    }
}

/// Text was typed (a TextTyped event): it goes in at the caret
pub fn OnTextTyped(self: *FocusSystem, engine_context: *EngineContext, typed: []const u8) !void {
    const copy = try engine_context.FrameAllocator().dupe(u8, typed);
    try self.Type(engine_context, copy);
}

/// Puts `bytes` in at the caret, without their line breaks: a text input is one line, and Enter ends the edit
fn Type(self: *FocusSystem, engine_context: *EngineContext, bytes: []u8) !void {
    const focused = self.Focused() orelse return;
    const text = focused.GetComponent(TextComponent) orelse return;
    const line = TextEdit.SingleLine(bytes, bytes);
    if (line.len == 0) return;

    self.mCaret = @min(self.mCaret, text.mText.items.len);
    self.mBlinkTime = 0;
    try TextEdit.Insert(engine_context.EngineAllocator(), &text.mText, &self.mCaret, line);
    try self.Changed(engine_context, focused);
}

/// Once a frame, after layout and before world transforms: keeps the caret on the text and blinking, and lets go if
/// the focused text input has gone
pub fn Update(self: *FocusSystem, engine_context: *EngineContext) !void {
    const focused = self.mFocused orelse return;
    if (!focused.IsActive()) {
        //deleted while being typed into, and its caret with it: there is no one left to tell
        self.Reset(engine_context);
        return;
    }
    if (!focused.HasComponent(TextInputComponent) or !focused.HasComponent(TextComponent)) {
        try self.EndEdit(engine_context, .Submit);
        return;
    }

    //typed text is one switch for the whole window, and an ImGui text field letting go of the keyboard turns it off
    engine_context.mAppWindow.StartTextInput();
    self.mBlinkTime += engine_context.mDT;
    try self.UpdateCaret(engine_context, focused);
}

fn UpdateCaret(self: *FocusSystem, engine_context: *EngineContext, focused: Entity) !void {
    const text = focused.GetComponent(TextComponent).?;
    self.mCaret = @min(self.mCaret, text.mText.items.len);
    const place = try CaretPlace(engine_context, text, self.mCaret);

    const caret = try self.CaretEntity(engine_context, focused);
    const quad = caret.GetComponent(QuadComponent).?;
    quad.mShouldRender = @mod(self.mBlinkTime, 2 * BLINK_SECONDS) < BLINK_SECONDS;
    quad.mSize = .{ .x = text.mFontSize * CARET_WIDTH, .y = place.Height };
    quad.mMaterial = text.mMaterial;

    const translation = Vec3(f32){ .x = place.Center.x, .y = place.Center.y, .z = CARET_DEPTH };
    const transform = caret.GetComponent(TransformComponent).?;
    const current = transform.GetTranslation();
    if (current.x != translation.x or current.y != translation.y or current.z != translation.z) {
        try caret.SetTranslation(engine_context, translation);
    }
}

/// The caret's quad, made the first time it is needed for each edit
fn CaretEntity(self: *FocusSystem, engine_context: *EngineContext, focused: Entity) !Entity {
    if (self.mCaretEntity) |caret| {
        if (caret.IsActive()) return caret;
    }
    const caret = try focused.CreateChild(engine_context, .Entity, Entity.DefaultConfig);
    if (caret.GetComponent(NameComponent)) |name| {
        name.mName.clearRetainingCapacity();
        try name.mName.appendSlice(engine_context.EngineAllocator(), "Caret");
    }
    _ = try caret.AddComponent(engine_context, QuadComponent{});
    self.mCaretEntity = caret;
    return caret;
}

/// Where the caret goes in the text input's own space, and how tall it is: the height of a line, from the
/// ascender to the descender. With no font yet it sits at the start, a font size tall
fn CaretPlace(engine_context: *EngineContext, text: *const TextComponent, caret_index: usize) !struct { Center: Vec2(f32), Height: f32 } {
    //lines start at the left bound (see ShapeGeometry.TextParams)
    const line_start = -text.mBounds.x;
    if (!text.mTextAssetHandle.IsIDValid()) {
        return .{ .Center = .{ .x = line_start, .y = text.mFontSize * 0.5 }, .Height = text.mFontSize };
    }
    const font = try text.mTextAssetHandle.GetAsset(engine_context, TextAsset);
    const pen = TextLayout.CaretPen(TextAsset, text.mText.items, font, text.mFontSize, WrapWidth(text), caret_index);
    const ascender = font.mAscender * text.mFontSize;
    const descender = font.mDescender * text.mFontSize;
    return .{
        .Center = .{ .x = line_start + pen.x, .y = pen.y + (ascender + descender) * 0.5 },
        .Height = ascender - descender,
    };
}

/// Moves the caret to the spot in the text nearest where the pointer went down. Stays where it is if that can't be
/// worked out: no font yet, or no view to place an overlay's point through
fn PlaceCaretAt(self: *FocusSystem, engine_context: *EngineContext, focused: Entity, pointer_input: PointerSystem.Input) !void {
    self.mBlinkTime = 0;
    const text = focused.GetComponent(TextComponent) orelse return;
    if (!text.mTextAssetHandle.IsIDValid()) return;
    const local = LocalPoint(focused, pointer_input) orelse return;
    const font = try text.mTextAssetHandle.GetAsset(engine_context, TextAsset);
    //lines start at the left bound, x = 0 for text layout
    const point = Vec2(f32){ .x = local.x + text.mBounds.x, .y = local.y };
    self.mCaret = TextLayout.CaretIndexAt(TextAsset, text.mText.items, font, text.mFontSize, WrapWidth(text), point);
}

/// Where the pointer went down, in `entity`'s own space: before its scale, the space its children and its text are
/// laid out in
fn LocalPoint(entity: Entity, pointer_input: PointerSystem.Input) ?Vec2(f32) {
    const transform = entity.GetComponent(TransformComponent) orelse return null;
    var point = pointer_input.Position;
    if (entity.GetLayer() == .OverlayLayer) {
        const view = pointer_input.View orelse return null;
        const scene = entity.GetComponent(EntitySceneComponent).?.mScene;
        point = ShapeGeometry.SceneCanvas(scene, view.CameraView).ToCanvasPoint(point);
    }
    const scale = transform.GetWorldScale();
    if (scale.x == 0 or scale.y == 0) return null;
    const local = point.SubVec(transform.GetWorldPosition()).InvQuatRotate(transform.GetWorldRotation());
    return .{ .x = local.x / scale.x, .y = local.y / scale.y };
}

/// The width the text wraps at in its own space, the same as the renderer's (ShapeGeometry.GetTextParams) before scale
fn WrapWidth(text: *const TextComponent) f32 {
    return text.mBounds.x + text.mBounds.y;
}

/// The text was edited: layout sizes text to fit, so it needs another pass
fn Changed(self: *FocusSystem, engine_context: *EngineContext, focused: Entity) !void {
    self.mBlinkTime = 0;
    try focused.MarkLayoutDirty(engine_context);
    try Send(engine_context, focused, .TextChanged);
}

fn ReleaseKeyboard(engine_context: *EngineContext) void {
    engine_context.mInputManager.mKeyboardTaken = false;
    engine_context.mAppWindow.StopTextInput();
}

/// One event of `kind` to the text input and to everything it is inside
fn Send(engine_context: *EngineContext, text_input: Entity, comptime kind: std.meta.Tag(UIEvent)) !void {
    const chain = try PointerSystem.ChainOf(engine_context.FrameAllocator(), text_input);
    for (chain.items) |entity| {
        const event = @unionInit(UIEvent, @tagName(kind), .{ .mEntity = entity, .mTarget = text_input });
        try engine_context.mUIEventManager.Insert(engine_context.EngineAllocator(), .Interaction, event);
    }
}

fn Same(a: Entity, b: Entity) bool {
    return a.mID == b.mID and a.mManager == b.mManager;
}

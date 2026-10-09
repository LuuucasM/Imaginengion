const std = @import("std");
const Inspector = @import("../../UI/Inspector.zig");
const AssetHandle = @import("../../ECSObjects/AssetHandle.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const MathTypes = @import("../../Math/MathTypes.zig");
const Vec4 = MathTypes.Vec4;
const Vec2 = MathTypes.Vec2;
const AssetsList = @import("../AComponents.zig");
const FileMetaData = AssetsList.FileMetaData;
const EngineContext = @import("../../Core/EngineContext.zig");
const TextComponent = @This();

const ImguiManager = @import("../../Imgui/Imgui.zig");

pub const Editable: bool = true;
pub const Name: []const u8 = "TextComponent";

//what it is painted with, the texture and color, is the entity's SurfaceComponent: text with no surface isn't drawn
mText: std.ArrayList(u8) = .empty,
mTextAssetHandle: AssetHandle = .uninit,
mFontSize: f32 = 9,
mBounds: Vec2(f32) = .{ .x = 8, .y = 8 },

pub fn Deinit(self: *TextComponent, engine_context: *EngineContext) void {
    self.mTextAssetHandle.ReleaseAsset();
    self.mText.deinit(engine_context.EngineAllocator());
}

pub fn Clone(self: *const TextComponent, engine_context: *EngineContext) !TextComponent {
    var new_component = self.*;

    new_component.mText = try self.mText.clone(engine_context.EngineAllocator());

    // the copy releases it itself, so it needs its own reference
    new_component.mTextAssetHandle.RetainAsset();

    return new_component;
}

/// Replaces the text. Layout doesn't see the change on its own, so if the entity is in a layout the caller
/// marks it with entity.MarkLayoutDirty
pub fn SetText(self: *TextComponent, engine_context: *EngineContext, text: []const u8) !void {
    self.mText.clearRetainingCapacity();
    try self.mText.appendSlice(engine_context.EngineAllocator(), text);
}

/// Adds to the end of the text. Same as SetText, the caller marks the layout dirty if the entity is in one
pub fn AppendText(self: *TextComponent, engine_context: *EngineContext, text: []const u8) !void {
    try self.mText.appendSlice(engine_context.EngineAllocator(), text);
}

pub fn UIRender(self: *TextComponent, ui: *Inspector.Builder) !void {
    try ui.Text(&self.mText, "Text", .{});
    try ui.Asset(&self.mTextAssetHandle, "Font", &.{ ".ttf", ".otf" }, .{});
    try ui.Float(&self.mFontSize, "Font Size", .{ .Speed = 0.5, .Min = 1 });
    try ui.Vec2Field(&self.mBounds, "Bounds", .{ .Speed = 0.1 });
}

pub fn EditorRender(self: *TextComponent, engine_context: *EngineContext) !void {
    try ImguiManager.RenderTextInput(engine_context, &self.mText, "Text");

    //font name just as a text that can be drag dropped onto to change the text
    try ImguiManager.RenderAssetRef(engine_context, &self.mTextAssetHandle, "Text Asset", "TextAsset");

    _ = try ImguiManager.RenderFloatInput(&self.mFontSize, "Font Size", 1, 5);

    //bounds, have sliders for left ([0]) and right ([1])
    try ImguiManager.RenderFloat2Drag(&self.mBounds, "Bounds L R", 0.1, 0, 0);
}

const Json = JsonUtils.JsonFields(TextComponent, .{
    .Text = "mText",
    .Font = "mTextAssetHandle",
    .FontSize = "mFontSize",
    .Bounds = "mBounds",
});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

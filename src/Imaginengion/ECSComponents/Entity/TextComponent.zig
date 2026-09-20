const std = @import("std");
const AssetHandle = @import("../../ECSObjects/AssetHandle.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const MathTypes = @import("../../Math/MathTypes.zig");
const Vec4 = MathTypes.Vec4;
const Vec2 = MathTypes.Vec2;
const AssetsList = @import("../AComponents.zig");
const FileMetaData = AssetsList.FileMetaData;
const Texture2D = @import("../AComponents.zig").Texture2D;
const EngineContext = @import("../../Core/EngineContext.zig");
const Material = @import("../../Physics/Material.zig");
const TextComponent = @This();

const ImguiManager = @import("../../Imgui/Imgui.zig");

pub const Editable: bool = true;
pub const Name: []const u8 = "TextComponent";

mShouldRender: bool = true,
mText: std.ArrayList(u8) = .empty,
mTextAssetHandle: AssetHandle = .uninit,
mTexHandle: AssetHandle = .uninit,
mTexOptions: Texture2D.TexOptions = .default,
mMaterial: Material.SurfaceRenderMat = .default,
mFontSize: f32 = 9,
mBounds: Vec2(f32) = .{ .x = 8, .y = 8 },
mEngineAllocator: std.mem.Allocator = undefined,
mShouldEditTexture: bool = false,

pub fn Deinit(self: *TextComponent, engine_context: *EngineContext) void {
    self.mTextAssetHandle.ReleaseAsset();
    self.mTexHandle.ReleaseAsset();
    self.mText.deinit(engine_context.EngineAllocator());
}

pub fn Clone(self: *const TextComponent, engine_context: *EngineContext) !TextComponent {
    var new_component = self.*;

    new_component.mText = try self.mText.clone(engine_context.EngineAllocator());

    // the copy releases these itself, so it needs its own references
    new_component.mTextAssetHandle.RetainAsset();
    new_component.mTexHandle.RetainAsset();

    return new_component;
}

pub fn EditorRender(self: *TextComponent, engine_context: *EngineContext) !void {
    try ImguiManager.RenderTextInput(engine_context, &self.mText, "Text");

    //font name just as a text that can be drag dropped onto to change the text
    try ImguiManager.RenderAssetRef(engine_context, &self.mTextAssetHandle, "Text Asset", "TextAsset");

    _ = try ImguiManager.RenderFloatInput(&self.mFontSize, "Font Size", 1, 5);

    //bounds, have sliders for left ([0]) and right ([1])
    try ImguiManager.RenderFloat2Drag(&self.mBounds, "Bounds L R", 0.1, 0, 0);

    const texture_asset = try self.mTexHandle.GetAsset(engine_context, Texture2D);
    try ImguiManager.RenderTexture2D(engine_context, &self.mTexHandle, texture_asset, &self.mShouldEditTexture);
    try self.mTexOptions.ImguiRender(engine_context, &self.mShouldEditTexture, texture_asset);

    try self.mMaterial.ImguiRender();
}

const Json = JsonUtils.JsonFields(TextComponent, .{
    .ShouldRender = "mShouldRender",
    .Text = "mText",
    .Font = "mTextAssetHandle",
    .Texture = "mTexHandle",
    .TexOptions = "mTexOptions",
    .Material = "mMaterial",
    .FontSize = "mFontSize",
    .Bounds = "mBounds",
});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

const std = @import("std");
const Inspector = @import("../../UI/Inspector.zig");
const MathTypes = @import("../../Math/MathTypes.zig");
const Vec4 = MathTypes.Vec4;
const Assets = @import("../AComponents.zig");
const Texture2D = Assets.Texture2D;
const AssetHandle = @import("../../ECSObjects/AssetHandle.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const EngineContext = @import("../../Core/EngineContext.zig");
const Material = @import("../../Physics/Material.zig");
const ImguiManager = @import("../../Imgui/Imgui.zig");
const SurfaceComponent = @This();

pub const Editable: bool = true;
pub const Name: []const u8 = "SurfaceComponent";

/// How an entity looks: what its ShapeComponent or its TextComponent is painted with. What is drawn and clicked is
/// everything with a surface. One per entity, so a shape and a text that look different are two entities
mShouldRender: bool = true,
mTexture: AssetHandle = .uninit,
mTexOptions: Texture2D.TexOptions = .default,
mMaterial: Material.SurfaceRenderMat = .default,
//a solid band of mBorderColor this wide around the shape's edge, inside it and following its rounded corners, in the
//same units as the shape's size. 0 for none. Text has no edge for it and ignores it
mBorderWidth: f32 = 0,
mBorderColor: Vec4(f32) = .{ .x = 0, .y = 0, .z = 0, .w = 1 },
mEditTexCoords: bool = false,

pub fn Deinit(self: *SurfaceComponent, _: *EngineContext) void {
    self.mTexture.ReleaseAsset();
}

pub fn Clone(self: *const SurfaceComponent, _: *EngineContext) !SurfaceComponent {
    var new_component = self.*;

    // the copy releases the texture itself, so it needs its own reference
    new_component.mTexture.RetainAsset();

    return new_component;
}

pub fn UIRender(self: *SurfaceComponent, ui: *Inspector.Builder) !void {
    try ui.Bool(&self.mShouldRender, "Should Render", .{});
    try ui.Float(&self.mBorderWidth, "Border Width", .{ .Speed = 0.01, .Min = 0 });
    try ui.Color(&self.mBorderColor, "Border Color", .{});
    try ui.Struct(&self.mMaterial, "Material");
    try ui.Asset(&self.mTexture, "Texture", &.{".png"}, .{ .Thumbnail = true });
    try ui.Fields(&self.mTexOptions);
}

pub fn EditorRender(self: *SurfaceComponent, engine_context: *EngineContext) !void {
    try ImguiManager.RenderBool(&self.mShouldRender, "Should Render?");

    _ = try ImguiManager.RenderFloatDrag(&self.mBorderWidth, "Border Width", 0.01, 0, std.math.floatMax(f32));
    try ImguiManager.RenderColor4Edit(&self.mBorderColor, "Border Color");

    try self.mMaterial.ImguiRender();

    const texture_asset = try self.mTexture.GetAsset(engine_context, Texture2D);

    try self.mTexOptions.ImguiRender(engine_context, &self.mEditTexCoords, texture_asset);

    try ImguiManager.RenderTexture2D(engine_context, &self.mTexture, texture_asset, &self.mEditTexCoords);
}

const Json = JsonUtils.JsonFields(SurfaceComponent, .{
    .ShouldRender = "mShouldRender",
    .Texture = "mTexture",
    .TexOptions = "mTexOptions",
    .Material = "mMaterial",
    .BorderWidth = "mBorderWidth",
    .BorderColor = "mBorderColor",
});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

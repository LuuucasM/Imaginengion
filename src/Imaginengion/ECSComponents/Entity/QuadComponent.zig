const std = @import("std");
const MathTypes = @import("../../Math/MathTypes.zig");
const Vec4 = MathTypes.Vec4;
const Vec2 = MathTypes.Vec2;
const Assets = @import("../AComponents.zig");
const Texture2D = Assets.Texture2D;
const FileMetaData = Assets.FileMetaData;
const AssetHandle = @import("../../ECSObjects/AssetHandle.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const AssetType = @import("../../Assets/AManager.zig").AssetType;
const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Player = @import("../../ECSObjects/Player.zig");
const RenderTargetComponent = @import("../EComponents.zig").RenderTargetComponent;
const Material = @import("../../Physics/Material.zig");
const ImguiManager = @import("../../Imgui/Imgui.zig");
const QuadComponent = @This();

pub const Editable: bool = true;
pub const Name: []const u8 = "QuadComponent";

mShouldRender: bool = true,
mTexture: AssetHandle = .uninit,
mTexOptions: Texture2D.TexOptions = .default,
mMaterial: Material.SurfaceRenderMat = .default,
mEditTexCoords: bool = false,

pub fn Deinit(self: *QuadComponent, _: *EngineContext) void {
    self.mTexture.ReleaseAsset();
}

pub fn Clone(self: *const QuadComponent, _: *EngineContext) !QuadComponent {
    var new_component = self.*;

    // the copy releases the texture itself, so it needs its own reference
    new_component.mTexture.RetainAsset();

    return new_component;
}

pub fn EditorRender(self: *QuadComponent, engine_context: *EngineContext) !void {
    try ImguiManager.RenderBool(&self.mShouldRender, "Should Render?");

    try self.mMaterial.ImguiRender();

    const texture_asset = try self.mTexture.GetAsset(engine_context, Texture2D);

    try self.mTexOptions.ImguiRender(engine_context, &self.mEditTexCoords, texture_asset);

    try ImguiManager.RenderTexture2D(engine_context, &self.mTexture, texture_asset, &self.mEditTexCoords);
}

const Json = JsonUtils.JsonFields(QuadComponent, .{
    .ShouldRender = "mShouldRender",
    .Texture = "mTexture",
    .TexOptions = "mTexOptions",
    .Material = "mMaterial",
});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

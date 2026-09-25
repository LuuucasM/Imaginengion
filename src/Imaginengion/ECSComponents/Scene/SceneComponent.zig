const EngineContext = @import("../../Core/EngineContext.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const OverlayCanvas = @import("../../Math/OverlayCanvas.zig");
const ImguiManager = @import("../../Imgui/Imgui.zig");
const imgui = @import("../../Core/CImports.zig").imgui;
const SceneComponent = @This();

pub const LayerType = enum(u1) {
    GameLayer = 0,
    OverlayLayer = 1,
};

pub const OverlayScaleMode = OverlayCanvas.OverlayScaleMode;

pub const Name: []const u8 = "SceneComponent";
//every scene needs one: the renderer and the scene stack read its layer type
pub const Removable: bool = false;

mLayerType: LayerType = .GameLayer,
//how the scene's units turn into screen pixels. the overlay renderer reads it for its canvas; game
//layer scenes are drawn through the camera, so for them it doesn't change anything yet
mOverlayScaleMode: OverlayScaleMode = .ScaleWithScreen,

pub fn Deinit(_: *SceneComponent, _: *EngineContext) void {}

/// How many screen pixels one canvas unit of this overlay scene covers, on a target this tall.
pub fn GetPixelsPerUnit(self: SceneComponent, target_height: f32, display_scale: f32) f32 {
    return OverlayCanvas.PixelsPerUnit(self.mOverlayScaleMode, target_height, display_scale);
}

pub fn EditorRender(self: *SceneComponent, _: *EngineContext) !void {
    //shown, not edited: the scene stack slots a scene by its layer when it is created
    imgui.igText("Layer: %s", @tagName(self.mLayerType).ptr);

    try ImguiManager.RenderEnum(OverlayScaleMode, &self.mOverlayScaleMode, "Scale Mode");
}

const Json = JsonUtils.JsonFields(SceneComponent, .{
    .LayerType = "mLayerType",
    .OverlayScaleMode = "mOverlayScaleMode",
});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

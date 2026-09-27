const EngineContext = @import("../../Core/EngineContext.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const OverlayCanvas = @import("../../Math/OverlayCanvas.zig");
const ImguiManager = @import("../../Imgui/Imgui.zig");
const SceneComponent = @This();

//a scene's layer is its GameLayerTag or OverlayLayerTag (see Scene.GetLayer)
pub const LayerType = @import("../Shared/TagComponents.zig").LayerType;

pub const OverlayScaleMode = OverlayCanvas.OverlayScaleMode;

pub const Name: []const u8 = "SceneComponent";
//every scene needs one: the overlay renderer reads its scale mode
pub const Removable: bool = false;

//how the scene's units turn into screen pixels. the overlay renderer reads it for its canvas; game
//layer scenes are drawn through the camera, so for them it doesn't change anything yet
mOverlayScaleMode: OverlayScaleMode = .ScaleWithScreen,

pub fn Deinit(_: *SceneComponent, _: *EngineContext) void {}

/// How many screen pixels one canvas unit of this overlay scene covers, on a target this tall.
pub fn GetPixelsPerUnit(self: SceneComponent, target_height: f32, display_scale: f32) f32 {
    return OverlayCanvas.PixelsPerUnit(self.mOverlayScaleMode, target_height, display_scale);
}

pub fn EditorRender(self: *SceneComponent, _: *EngineContext) !void {
    try ImguiManager.RenderEnum(OverlayScaleMode, &self.mOverlayScaleMode, "Scale Mode");
}

const Json = JsonUtils.JsonFields(SceneComponent, .{
    .OverlayScaleMode = "mOverlayScaleMode",
});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

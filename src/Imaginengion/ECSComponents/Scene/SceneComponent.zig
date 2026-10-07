const EngineContext = @import("../../Core/EngineContext.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const Vec2 = @import("../../Math/MathTypes.zig").Vec2;
const SceneComponent = @This();

//a scene's layer is its GameLayerTag or OverlayLayerTag (see Scene.GetLayer)
pub const LayerType = @import("../Shared/TagComponents.zig").LayerType;

pub const Name: []const u8 = "SceneComponent";
//every scene needs one: layout reads the screen an overlay scene was last drawn on from it
pub const Removable: bool = false;

//how an overlay scene's units turn into screen pixels is its world's, shared by every overlay scene in it (see
//WorldManager.mOverlayScaleMode), so they all measure the one screen space the same way

/// For an overlay scene, the screen in canvas units (width / k by height / k) as of the last time a view drew it:
/// what its layout roots size and anchor against. Null until it has been drawn. Recorded by the renderer, never
/// saved: it belongs to whatever view the scene is in, not to the scene
mLayoutArea: ?Vec2(f32) = null,

pub fn Deinit(_: *SceneComponent, _: *EngineContext) void {}

//nothing of it is saved any more. an old file's OverlayScaleMode key is skipped
const Json = JsonUtils.JsonFields(SceneComponent, .{});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

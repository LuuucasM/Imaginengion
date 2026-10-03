const EngineContext = @import("../../Core/EngineContext.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");

const ClipComponent = @This();

pub const Editable: bool = false;
pub const Name: []const u8 = "ClipComponent";

/// Cuts off everything under the entity (its children, and theirs) at the edges of its rectangle: what layout sized it
/// to, or its quad's size if it isn't in a layout. An SDF intersection, so it works on any shape the renderer draws, in
/// either layer, not just UI. Its own quad isn't cut, it is the rectangle. Drawing and picking both stop at the edge, so
/// a hidden part can't be clicked; physics doesn't. A clip inside another clip is cut to both. The cut goes through
/// depth, so children in front of or behind the entity are cut the same. Scrolling what it cuts is UI, see the UI
/// element's ScrollComponent

pub fn Deinit(_: *ClipComponent, _: *EngineContext) void {}

//nothing of its own to save. Files from before it was only a clip still have its old scroll settings in it, skipped
const Json = JsonUtils.JsonFields(ClipComponent, .{});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

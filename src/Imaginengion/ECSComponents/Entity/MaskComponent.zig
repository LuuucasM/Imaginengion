const EngineContext = @import("../../Core/EngineContext.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const ImguiManager = @import("../../Imgui/Imgui.zig");
const SDFProgram = @import("../../Renderer/SDFProgram.zig");

const MaskComponent = @This();

pub const Editable: bool = true;
pub const Name: []const u8 = "MaskComponent";

/// Cuts everything under the entity (its children, and theirs, game objects of their own too) with the entity's own
/// shape (ShapeComponent), rounded corners and all: Intersect keeps only what is inside it, Subtract cuts it out. Each
/// thing under it stays its own shape, cut separately, so it is still drawn and clicked as itself. The entity's own
/// shape isn't cut, and is only drawn if it has a surface, so a mask can be invisible. A 2D shape cuts straight through
/// depth, so things in front of or behind it are cut the same. A mask inside another is cut by both. Drawing and
/// picking both stop at the cut, physics doesn't. An entity with no shape cuts nothing. Scrolling what it cuts is UI,
/// see the UI element's ScrollComponent
mOp: SDFProgram.MaskOp = .Intersect,

pub fn Deinit(_: *MaskComponent, _: *EngineContext) void {}

pub fn EditorRender(self: *MaskComponent, _: *EngineContext) !void {
    try ImguiManager.RenderEnum(SDFProgram.MaskOp, &self.mOp, "Op");
}

const Json = JsonUtils.JsonFields(MaskComponent, .{
    .Op = "mOp",
});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

const EngineContext = @import("../../Core/EngineContext.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");

const MergeComponent = @This();

pub const Editable: bool = false;
pub const Name: []const u8 = "MergeComponent";

/// Makes the entity's shape and every shape under it one shape, a compound SDF: each part adds to it, cuts into it or
/// trims it by its CombineOpComponent (a Union without one), smoothly or not. Every add comes first, then every
/// subtract, then every intersect, so the order of the hierarchy never changes the shape. The parts are all the
/// entities below it with a ShapeComponent, through any without one, but not into a game object of its own
/// (MainObjectComponent). A merge under it is one part, its own shape in brackets, joined by its root's
/// CombineOpComponent. Each part is painted with its own surface's color, blended where they meet; a part with no
/// surface takes the color of what it is merged into. SDFCompiler turns it into what the renderer runs

pub fn Deinit(_: *MergeComponent, _: *EngineContext) void {}

const Json = JsonUtils.JsonFields(MergeComponent, .{});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

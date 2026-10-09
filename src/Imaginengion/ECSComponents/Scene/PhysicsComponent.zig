const Vec3 = @import("../../Math/MathTypes.zig").Vec3;
const Inspector = @import("../../UI/Inspector.zig");
const EngineContext = @import("../../Core/EngineContext.zig");
const PhysicsComponent = @This();

const JsonUtils = @import("../../Serializer/JsonUtils.zig");

pub const Name: []const u8 = "PhysicsComponent";

mGravity: Vec3(f32) = .{ .x = 0.0, .y = -9.81, .z = 0.0 },

pub fn Deinit(_: *PhysicsComponent, _: *EngineContext) void {}

pub fn UIRender(self: *PhysicsComponent, ui: *Inspector.Builder) !void {
    try ui.Vec3Field(&self.mGravity, "Gravity", .{ .Speed = 0.1 });
}

const Json = JsonUtils.JsonFields(PhysicsComponent, .{ .Gravity = "mGravity" });
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

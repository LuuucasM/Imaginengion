const BuiltinComponentCount = @import("../../ECS/Components.zig").BuiltinComponentCount;
const Vec3 = @import("../../Math/MathTypes.zig").Vec3;
const ComponentsList = @import("../SceneComponents.zig").ComponentsList;
const EngineContext = @import("../../Core/EngineContext.zig");
const PhysicsComponent = @This();

const ImguiManager = @import("../../Imgui/Imgui.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");

pub const Name: []const u8 = "PhysicsComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == PhysicsComponent) {
            break :blk i + BuiltinComponentCount;
        }
    }
};

mGravity: Vec3(f32) = .{ .x = 0.0, .y = -9.81, .z = 0.0 },

pub fn Deinit(_: *PhysicsComponent, _: *EngineContext) !void {}

pub fn EditorRender(self: *PhysicsComponent, _: *EngineContext) !void {
    try ImguiManager.RenderFloat3Input(&self.mGravity, "Gravity");
}

const Json = JsonUtils.JsonFields(PhysicsComponent, .{ .Gravity = "mGravity" });
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

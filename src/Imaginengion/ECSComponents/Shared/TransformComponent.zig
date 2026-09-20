const std = @import("std");
const MathTypes = @import("../../Math/MathTypes.zig");
const MathUtils = @import("../../Math/MathUtils.zig");
const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");

//imgui stuff
const ImguiManager = @import("../../Imgui/Imgui.zig");

const Vec3 = MathTypes.Vec3;
const Quat = MathTypes.Quat;
const Mat4 = MathTypes.Mat4;

const TransformComponent = @This();

const InternalData = struct {
    WorldPosition: Vec3(f32) = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
    WorldRotation: Quat(f32) = .{ .w = 1.0, .x = 0.0, .y = 0.0, .z = 0.0 },
    WorldScale: Vec3(f32) = .{ .x = 2.0, .y = 2.0, .z = 2.0 },
};

pub const Editable: bool = true;
pub const Name: []const u8 = "TransformComponent";

pub const empty: TransformComponent = .{
    .Translation = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
    .Rotation = .{ .w = 1.0, .x = 0.0, .y = 0.0, .z = 0.0 },
    .Scale = .{ .x = 2.0, .y = 2.0, .z = 2.0 },
};

Translation: Vec3(f32) = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
Rotation: Quat(f32) = .{ .w = 1.0, .x = 0.0, .y = 0.0, .z = 0.0 },
Scale: Vec3(f32) = .{ .x = 2.0, .y = 2.0, .z = 2.0 },

_InternalData: InternalData = .{},

pub fn Deinit(_: *TransformComponent, _: *EngineContext) void {}

pub fn GetWorldPosition(self: TransformComponent) Vec3(f32) {
    return self._InternalData.WorldPosition;
}
pub fn SetWorldPosition(self: *TransformComponent, new_pos: Vec3(f32)) void {
    self._InternalData.WorldPosition = new_pos;
}
pub fn GetWorldRotation(self: TransformComponent) Quat(f32) {
    return self._InternalData.WorldRotation;
}
pub fn SetWorldRotation(self: *TransformComponent, new_rot: Quat(f32)) void {
    self._InternalData.WorldRotation = new_rot;
}
pub fn GetWorldScale(self: TransformComponent) Vec3(f32) {
    return self._InternalData.WorldScale;
}
pub fn SetWorldScale(self: *TransformComponent, new_scale: Vec3(f32)) void {
    self._InternalData.WorldScale = new_scale;
}

pub fn EditorRender(self: *TransformComponent, _: *EngineContext) !void {
    try ImguiManager.RenderVec3(&self.Translation, "Translation", 0.0, 0.075, 100.0);
    try ImguiManager.RenderQuat(&self.Rotation, "Rotation", 0, 0.25, 100.0);
    try ImguiManager.RenderVec3(&self.Scale, "Scale", 1.0, 0.075, 100.0);
}

const Json = JsonUtils.JsonFields(TransformComponent, .{
    .Translation = "Translation",
    .Rotation = "Rotation",
    .Scale = "Scale",
});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

pub fn PostParse(_: *TransformComponent, _: *EngineContext, owning_entity: Entity) !void {
    owning_entity._CalculateWorldTransform();
}

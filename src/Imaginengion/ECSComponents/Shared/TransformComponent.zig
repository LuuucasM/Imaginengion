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
    ._Translation = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
    ._Rotation = .{ .w = 1.0, .x = 0.0, .y = 0.0, .z = 0.0 },
    ._Scale = .{ .x = 2.0, .y = 2.0, .z = 2.0 },
};

//the local transform is private so that every write goes through Entity's setters, which are
//what add the TransformDirtyComponent tag. A direct write here would leave the entity untagged
//and UpdateWorldTransforms would never recompute its world transform. Reads are free: use the
//Get* accessors, or GetWorld* for the value the last transform pass produced.
_Translation: Vec3(f32) = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
_Rotation: Quat(f32) = .{ .w = 1.0, .x = 0.0, .y = 0.0, .z = 0.0 },
_Scale: Vec3(f32) = .{ .x = 2.0, .y = 2.0, .z = 2.0 },

_InternalData: InternalData = .{},

pub fn Deinit(_: *TransformComponent, _: *EngineContext) void {}

pub fn GetTranslation(self: TransformComponent) Vec3(f32) {
    return self._Translation;
}
pub fn GetRotation(self: TransformComponent) Quat(f32) {
    return self._Rotation;
}
pub fn GetScale(self: TransformComponent) Vec3(f32) {
    return self._Scale;
}

/// Writes the local transform without tagging the entity. Entity's SetTranslation/SetRotation/
/// SetScale call this and then add the tag; nothing else should, because an untagged write is
/// invisible to UpdateWorldTransforms.
pub fn _SetLocalUntagged(self: *TransformComponent, translation: Vec3(f32), rotation: Quat(f32), scale: Vec3(f32)) void {
    self._Translation = translation;
    self._Rotation = rotation;
    self._Scale = scale;
}

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
    //ImGui edits the fields in place, so the panel cannot go through Entity's setters. It marks
    //the object dirty itself after this returns (see ComponentsPanel.PrintObjectComponent).
    try ImguiManager.RenderVec3(&self._Translation, "Translation", 0.0, 0.075, 100.0);
    try ImguiManager.RenderQuat(&self._Rotation, "Rotation", 0, 0.25, 100.0);
    try ImguiManager.RenderVec3(&self._Scale, "Scale", 1.0, 0.075, 100.0);
}

const Json = JsonUtils.JsonFields(TransformComponent, .{
    .Translation = "_Translation",
    .Rotation = "_Rotation",
    .Scale = "_Scale",
});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

pub fn PostParse(_: *TransformComponent, _: *EngineContext, owning_entity: Entity) !void {
    owning_entity._CalculateWorldTransform();
}

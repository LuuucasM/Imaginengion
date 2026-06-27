const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const MathTypes = @import("../../Math/MathTypes.zig");
const MathUtils = @import("../../Math/MathUtils.zig");
const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../Entity.zig");

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
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == TransformComponent) {
            break :blk i + 5; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

Translation: Vec3(f32) = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
Rotation: Quat(f32) = .{ .w = 1.0, .x = 0.0, .y = 0.0, .z = 0.0 },
Scale: Vec3(f32) = .{ .x = 2.0, .y = 2.0, .z = 2.0 },

_InternalData: InternalData = .{},

pub fn Deinit(_: *TransformComponent, _: *EngineContext) !void {}

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
    ImguiManager.RenderVec3(&self.Translation, "Translation", 0.0, 0.075, 100.0);
    ImguiManager.RenderQuat(&self.Rotation, "Rotation", 0, 0.25, 100.0);
    ImguiManager.RenderVec3(&self.Scale, "Scale", 1.0, 0.075, 100.0);
}

pub fn jsonStringify(self: *const TransformComponent, jw: anytype) !void {
    try jw.beginObject();

    try jw.objectField("Translation");
    try jw.write(self.Translation);

    try jw.objectField("Rotation");
    try jw.write(self.Rotation);

    try jw.objectField("Scale");
    try jw.write(self.Scale);

    try jw.endObject();
}

pub fn jsonParse(frame_allocator: std.mem.Allocator, reader: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(reader.*))!TransformComponent {
    if (.object_begin != try reader.next()) return error.UnexpectedToken;

    var result: TransformComponent = .{};

    while (true) {
        const token = try reader.next();

        const field_name = switch (token) {
            .object_end => break,
            .string => |v| v,
            else => return error.UnexpectedToken,
        };

        if (std.mem.eql(u8, field_name, "Translation")) {
            result.Translation = try std.json.innerParse(Vec3(f32), frame_allocator, reader, options);
        } else if (std.mem.eql(u8, field_name, "Rotation")) {
            result.Rotation = try std.json.innerParse(Quat(f32), frame_allocator, reader, options);
        } else if (std.mem.eql(u8, field_name, "Scale")) {
            result.Scale = try std.json.innerParse(Vec3(f32), frame_allocator, reader, options);
        }
    }

    return result;
}

pub fn PostParse(_: TransformComponent, owning_entity: Entity) !void {
    owning_entity._CalculateWorldTransform();
}

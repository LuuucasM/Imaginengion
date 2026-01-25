const std = @import("std");
const Vec3f32 = @import("../../Math/LinAlg.zig").Vec3f32;
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;
const EngineContext = @import("../../Core/EngineContext.zig");
const ComponentsList = @import("../Components.zig").ComponentsList;
const Entity = @import("../Entity.zig");

//IMGUI
const imgui = @import("../../Core/CImports.zig").imgui;

const ColliderComponent = @This();

pub const Sphere = struct {
    mRadius: f32 = 1.0,
};

pub const Box = struct {
    mHalfExtents: Vec3f32 = Vec3f32{ 0.5, 0.5, 0.5 },
};

pub const UColliderShape = union(enum) {
    Sphere: Sphere,
    Box: Box,
};

pub const Category: ComponentCategory = .Multiple;
pub const Editable: bool = true;
pub const Name: []const u8 = "ColliderComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == ColliderComponent) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

mParent: Entity.Type = Entity.NullEntity,
mFirst: Entity.Type = Entity.NullEntity,
mPrev: Entity.Type = Entity.NullEntity,
mNext: Entity.Type = Entity.NullEntity,
mColliderShape: UColliderShape = .{ .Sphere = .{} },

pub fn Deinit(_: *ColliderComponent, _: *EngineContext) !void {}

pub fn AsSphere(self: *ColliderComponent) *Sphere {
    return &self.mColliderShape.Sphere;
}

pub fn AsBox(self: *ColliderComponent) *Box {
    return &self.mColliderShape.Box;
}

pub fn EditorRender(self: *ColliderComponent, _: *EngineContext) !void {
    const shape_names = [_][]const u8{ "Box", "Sphere" };
    var current_shape: i32 = @intFromEnum(self.mColliderShape);
    const preview_text: []const u8 = shape_names[@as(usize, @intCast(current_shape))];
    var preview_buf: [16]u8 = undefined;
    const preview_cstr = try std.fmt.bufPrintZ(&preview_buf, "{s}", .{preview_text});

    if (imgui.igBeginCombo("Audio Type", @ptrCast(preview_cstr.ptr), imgui.ImGuiComboFlags_None)) {
        defer imgui.igEndCombo();

        for (shape_names, 0..) |name, i| {
            var name_buf: [16]u8 = undefined;
            const name_cstr = try std.fmt.bufPrintZ(&name_buf, "{s}", .{name});
            const is_selected = (current_shape == @as(i32, @intCast(i)));
            if (imgui.igSelectable_Bool(name_cstr.ptr, is_selected, 0, .{ .x = 0, .y = 0 })) {
                current_shape = @as(i32, @intCast(i));
                self.mColliderShape = @enumFromInt(@as(u8, @intCast(current_shape)));
            }
            if (is_selected) {
                imgui.igSetItemDefaultFocus();
            }
        }
    }
}

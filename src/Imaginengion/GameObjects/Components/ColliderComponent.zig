const std = @import("std");
const Vec3f32 = @import("../../Math/LinAlg.zig").Vec3f32;
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
    const shape_names = [_][]const u8{ "Sphere", "Box" };

    const current_tag = @as(std.meta.Tag(UColliderShape), self.mColliderShape);
    const current_index = @intFromEnum(current_tag);

    const preview_text = shape_names[current_index];
    var preview_buf: [32]u8 = undefined;
    const preview_cstr = try std.fmt.bufPrintZ(&preview_buf, "{s}", .{preview_text});

    if (imgui.igBeginCombo("Collider Type", @ptrCast(preview_cstr.ptr), 0)) {
        defer imgui.igEndCombo();

        for (shape_names, 0..) |name, i| {
            var name_buf: [32]u8 = undefined;
            const name_cstr = try std.fmt.bufPrintZ(&name_buf, "{s}", .{name});
            const is_selected = (current_index == i);

            if (imgui.igSelectable_Bool(name_cstr.ptr, is_selected, 0, .{ .x = 0, .y = 0 })) {
                const new_tag: std.meta.Tag(UColliderShape) = @enumFromInt(i);
                self.mColliderShape = switch (new_tag) {
                    .Sphere => .{ .Sphere = .{} },
                    .Box => .{ .Box = .{} },
                };
            }
            if (is_selected) imgui.igSetItemDefaultFocus();
        }
    }

    switch (self.mColliderShape) {
        .Sphere => |*collider| {
            _ = imgui.igInputFloat("Radius", &collider.mRadius, 0.1, 1.0, "%.3f", 0);
        },
        .Box => |*collider| {
            _ = imgui.igInputFloat3("Half Extents", &collider.mHalfExtents[0], "%.3f", 0);
        },
    }
}

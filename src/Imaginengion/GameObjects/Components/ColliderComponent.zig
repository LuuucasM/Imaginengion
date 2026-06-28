const std = @import("std");
const Vec3 = @import("../../Math/MathTypes.zig").Vec3;
const EngineContext = @import("../../Core/EngineContext.zig");
const ComponentsList = @import("../Components.zig").ComponentsList;
const ImguiManager = @import("../../Imgui/Imgui.zig");
const Entity = @import("../Entity.zig");

//IMGUI
const imgui = @import("../../Core/CImports.zig").imgui;

const ColliderComponent = @This();

pub const Sphere = struct {
    mRadius: f32 = 1.0,

    const default = Sphere{ .mRadius = 1.0 };

    pub fn EditorRender(self: *Sphere) !void {
        try ImguiManager.RenderFloatInput(&self.mRadius, "Radius", 0.1, 1.0);
    }
};

pub const Box = struct {
    mHalfExtents: Vec3(f32) = Vec3(f32){ .x = 1, .y = 1, .z = 1 },

    const default = Box{ .mHalfExtents = Vec3(f32){ .x = 1, .y = 1, .z = 1 } };

    pub fn EditorRender(self: *Box) void {
        ImguiManager.RenderVec3(&self.mHalfExtents, "Half Extents", 0.5, 0.075, 100.0);
    }
};

pub const UColliderShape = union(enum) {
    Sphere: Sphere,
    Box: Box,
    pub fn EditorRender(self: *UColliderShape) !void {
        switch (self.*) {
            .Box => self.Box.EditorRender(),
            .Sphere => try self.Sphere.EditorRender(),
        }
    }
};

pub const Editable: bool = true;
pub const Name: []const u8 = "ColliderComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == ColliderComponent) {
            break :blk i + 5; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

mColliderShape: UColliderShape = .{ .Sphere = .{} },

pub fn Deinit(_: *ColliderComponent, _: *EngineContext) !void {}

pub fn AsSphere(self: *ColliderComponent) *Sphere {
    return &self.mColliderShape.Sphere;
}

pub fn AsBox(self: *ColliderComponent) *Box {
    return &self.mColliderShape.Box;
}

pub fn EditorRender(self: *ColliderComponent, _: *EngineContext) !void {
    try ImguiManager.RenderUnion(UColliderShape, &self.mColliderShape, "Collider Type");
}

pub fn jsonStringify(self: *const ColliderComponent, jw: anytype) !void {
    try jw.beginObject();

    try jw.objectField("Shape");
    try jw.write(self.mColliderShape);

    try jw.endObject();
}

pub fn jsonParse(frame_allocator: std.mem.Allocator, reader: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(reader.*))!ColliderComponent {
    if (.object_begin != try reader.next()) return error.UnexpectedToken;

    var result: ColliderComponent = .{};

    while (true) {
        const token = try reader.next();

        const field_name = switch (token) {
            .object_end => break,
            .string => |v| v,
            else => return error.UnexpectedToken,
        };

        if (std.mem.eql(u8, field_name, "Shape")) {
            const shape = try std.json.innerParse(UColliderShape, frame_allocator, reader, options);
            result.mColliderShape = shape;
        }
    }

    return result;
}

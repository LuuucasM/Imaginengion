const std = @import("std");
const Inspector = @import("../../UI/Inspector.zig");
const MathTypes = @import("../../Math/MathTypes.zig");
const Vec4 = MathTypes.Vec4;
const Vec2 = MathTypes.Vec2;
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const EngineContext = @import("../../Core/EngineContext.zig");
const ImguiManager = @import("../../Imgui/Imgui.zig");
const ShapeComponent = @This();

pub const Editable: bool = true;
pub const Name: []const u8 = "ShapeComponent";

/// What shape the entity is: only its geometry. How it looks is its SurfaceComponent, and an entity with a shape but no
/// surface isn't drawn or clicked
mKind: Kind = .{ .Quad = .{} },

pub const Kind = union(enum) {
    Quad: Quad,
};

/// A flat 2D rectangle, a plate THICKNESS_2D deep
pub const Quad = struct {
    //full width and height at scale 1. the transform's scale multiplies it, and the renderer halves it
    //into the half extents the GPU wants
    Size: Vec2(f32) = .{ .x = 1, .y = 1 },
    //how far in each corner is rounded, in the same units as Size, in the order the rounded SDFs take them:
    //x top right, y bottom right, z top left, w bottom left. 0 is a square corner
    CornerRadii: Vec4(f32) = .{ .x = 0, .y = 0, .z = 0, .w = 0 },

    pub fn UIRender(self: *Quad, ui: *Inspector.Builder) !void {
        //a negative size would turn the box inside out
        try ui.Vec2Field(&self.Size, "Size", .{ .Speed = 0.05, .Min = 0 });
        //the renderer keeps each radius to at most half the quad's smaller side
        try ui.Vec4Field(&self.CornerRadii, "Corner Radii", .{ .Speed = 0.01, .Min = 0 });
        try ui.Note("top right, bottom right, top left, bottom left");
    }
};

pub fn Deinit(_: *ShapeComponent, _: *EngineContext) void {}

/// A quad shape
pub fn MakeQuad(quad: Quad) ShapeComponent {
    return .{ .mKind = .{ .Quad = quad } };
}

/// The quad, if the shape is one
pub fn GetQuad(self: *ShapeComponent) ?*Quad {
    return switch (self.mKind) {
        .Quad => |*quad| quad,
    };
}

pub fn UIRender(self: *ShapeComponent, ui: *Inspector.Builder) !void {
    try ui.Union(&self.mKind, "Shape", .{});
}

pub fn EditorRender(self: *ShapeComponent, _: *EngineContext) !void {
    switch (self.mKind) {
        .Quad => |*quad| {
            //a negative size would turn the box inside out
            try ImguiManager.RenderFloat2Drag(&quad.Size, "Size", 0.05, 0, std.math.floatMax(f32));

            //the renderer keeps each radius and the border to at most half the quad's smaller side
            try ImguiManager.RenderText("Corner radii: top right, bottom right, top left, bottom left");
            try ImguiManager.RenderFloat4Drag(&quad.CornerRadii, "Corner Radii", 0.01, 0, std.math.floatMax(f32));
        },
    }
}

const Json = JsonUtils.JsonFields(ShapeComponent, .{
    .Kind = "mKind",
});
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;

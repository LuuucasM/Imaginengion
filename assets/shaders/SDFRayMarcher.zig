const std = @import("std");
const QuadData = @import("../../src/Imaginengion/Renderer/Renderer2D.zig").QuadData;
const GlyphData = @import("../../src/Imaginengion/Renderer/Renderer2D.zig").GlyphData;
const SDFCircularBuff = @import("SDFCircularBuff.zig");
const LinAlg = @import("../../src/Imaginengion/Math/LinAlg.zig");
const RayMarcher = @This();

const MAX_STEPS: u32 = 512;

const ShapeType = enum {
    None = 0,
    Quad,
    Glyph,
};

const ObjectData = struct {
    shape_type: ShapeType,
    shape_ind: u32,
};

const DistData = struct {
    min_dist: f32,
    object: ObjectData,
};

const ExcludeBuff = SDFCircularBuff.CircularHistory(ObjectData, 3);

mQuads: []QuadData,
mGlyphs: []GlyphData,
mRay: LinAlg.Ray,
mPerspectiveFar: f32,
mExclusions: ExcludeBuff = .empty,

pub fn March(self: RayMarcher) @Vector(4, f32) {
    var out_color = @Vector(3, f32){ 0, 0, 0 };
    var out_alpha: f32 = 0;
    var dist_origin: f32 = 0;

    var i: u32 = 0;
    while (i < MAX_STEPS) : (i += 1) {
        const point = self.mRayOrigin + @as(@Vector(3, f32), @splat(dist_origin)) * self.mRayDir;
        const step = self.ShortestDist(point);
    }
}

fn ShortestDist(self: RayMarcher, point: @Vector(3, f32)) DistData {
    var data = DistData{ .min_dist = 0, .object = .{ .shape_type = .None, .shape_ind = 0 } };

    for (self.mQuads, 0..) |quad, i| {
        if (self.mExclusions.contains(.{ .shape_type = .Quad, .shape_ind = i })) continue;
        const dist = IMQuad(point, quad.Position, quad.Rotation, quad.Scale);
    }
}

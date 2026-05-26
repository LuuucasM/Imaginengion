const std = @import("std");
const gpu = std.gpu;

const PushConstants = @import("IM").PushConstants;
const QuadData = @import("IM").QuadData;
const GlyphData = @import("IM").GlyphData;
const RayMarcher = @import("IM");
const Vec2 = @import("IM").Vec2;
const Vec3 = @import("IM").Vec3;
const Quat = @import("IM").Quat;

// layout(location = 0) out vec4 oFragColor
const oFragColor = @extern(*addrspace(.output) @Vector(4, f32), .{
    .name = "oFragColor",
    .decoration = .{ .location = 0 },
});

// layout(set = 3, binding = 0) uniform CameraUBO
const CameraUBO = @extern(*addrspace(.uniform) PushConstants, .{ .name = "CameraUBO", .decoration = .{ .descriptor = 3, .location = 0 } });
var QuadsSSBO = @extern(*addrspace(.storage_buffer) [*]QuadData, .{ .name = "QuadsSSBO", .decoration = .{ .descriptor = 2, .location = 1 } });
var GlyphsSSBO = @extern(*addrspace(.storage_buffer) [*]GlyphData, .{ .name = "GlyphsSSBO", .decoration = .{ .descriptor = 2, .location = 2 } });

export fn main() callconv(.spirv_fragment) void {
    const frag = gpu.frag_coord;

    const uv = Vec2(f32).FromVector(CameraUBO.mRayScale).MulVec(Vec2(f32){ .x = frag[0], .y = frag[1] }).AddVec(Vec2(f32).FromVector(CameraUBO.mRayOffset));

    const dir = Vec3(f32).Dir(.{ .x = uv.x, .y = uv.y, .z = -1.0 });
    const ray_dir = dir.QuatRotate(Quat(f32).FromVector(CameraUBO.mRotation));

    var marcher = RayMarcher{
        .mQuads = QuadsSSBO[0..CameraUBO.mQuadsCount],
        .mGlyphs = GlyphsSSBO[0..CameraUBO.mGlyphsCount],
        .mRay = .{ .Origin = CameraUBO.mPosition, .Direction = ray_dir },
        .mPerspectiveFar = CameraUBO.mPerspectiveFar,
    };
    marcher.mNodes[0] = .{ .SurfaceColor = .{ .x = 0, .y = 0, .z = 0, .w = 0 }, .FirstRay = 0, .ParentRay = -1, .Is2D = false };
    marcher.mNodeCount = 1;
    marcher.mEdges[0] = .{ .Ray = .{ .Origin = CameraUBO.mPosition, .Direction = ray_dir }, .FromNode = 0, .SiblingNode = -1, .ToNode = -1, .Length = -1 };
    marcher.mEdgeCount = 1;

    marcher.March();

    oFragColor = marcher.GenerateColor();
}

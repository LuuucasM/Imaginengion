const std = @import("std");
const gpu = std.gpu;

const PushConstants = @import("IM").PushConstants;
const QuadData = @import("IM").QuadData;
const GlyphData = @import("IM").GlyphData;
const ShadingData = @import("IM").ShadingData;
const RayMarcher = @import("IM").RayMarcher;
const Vec2 = @import("IM").Vec2;
const Vec3 = @import("IM").Vec3;
const Vec4 = @import("IM").Vec4;
const Quat = @import("IM").Quat;

// layout(location = 0) out vec4 oFragColor
const oFragColor = @extern(*addrspace(.output) @Vector(4, f32), .{
    .name = "oFragColor",
    .decoration = .{ .location = 0 },
});

// layout(set = 3, binding = 0) uniform PushConstnats
const CameraUBO = @extern(*addrspace(.uniform) PushConstants, .{ .name = "CameraUBO", .decoration = .{ .descriptor = .{ .set = 3, .binding = 0 } } });

//layout(set = 2, binding = 0) uniform sampler2DArray uTextures;
//NOTE: no samplers yet but its coming

//layout(set = 2, binding = 1) readonly buffer QuadsSSBO { QuadData data[]; } Quads;
const QuadsSSBO = @extern([*]addrspace(.storage_buffer) QuadData, .{ .name = "QuadsSSBO", .decoration = .{ .descriptor = .{ .set = 2, .binding = 1 } } });

//layout(set = 2, binding = 2) readonly buffer GlyphSSBO { GlyphData data[]; } Glyphs;
const GlyphsSSBO = @extern([*]addrspace(.storage_buffer) GlyphData, .{ .name = "GlyphsSSBO", .decoration = .{ .descriptor = .{ .set = 2, .binding = 2 } } });

//layout(set = 2, binding = 3) readonly buffer ShadingSSBO { ShadingData data[]; } Shading;
const ShadingSSBO = @extern([*]addrspace(.storage_buffer) ShadingData, .{ .name = "ShadingSSBO", .decoration = .{ .descriptor = .{ .set = 2, .binding = 3 } } });

export fn main() callconv(.spirv_fragment) void {
    const frag = gpu.frag_coord;

    const uv = Vec2(f32).FromVector(CameraUBO.mRayScale).MulVec(Vec2(f32){ .x = frag[0], .y = frag[1] }).AddVec(Vec2(f32).FromVector(CameraUBO.mRayOffset));

    const dir = Vec3(f32).Dir(.{ .x = uv.x, .y = uv.y, .z = -1.0 });
    const ray_dir = dir.QuatRotate(Quat(f32).FromVector(CameraUBO.mRotation));
    //
    var marcher = RayMarcher{
        .mNodes = undefined,
        .mEdges = undefined,
        .mNodeCount = 0,
        .mEdgeCount = 0,
    };
    marcher.mNodes[0] = .{
        .ParentEdge = -1,
        .MaterialHandle = 0,
        .FirstEdge = 0,
        .AccumColor = .{ .x = 0, .y = 0, .z = 0, .w = 0 },
    };
    marcher.mNodeCount = 1;

    marcher.mEdges[0] = .{
        .Ray = .{ .Origin = Vec3(f32).FromVector(CameraUBO.mPosition), .Direction = ray_dir },
        .Length = 0,
        .FromNode = 0,
        .ToNode = -1,
        .SiblingEdge = -1,
        .Normal = Vec3(f32){ .x = 0, .y = 0, .z = 0 },
        .AccumColor = Vec4(f32){ .x = 0, .y = 0, .z = 0, .w = 0 },
        .MaterialHandle = 0,
    };
    marcher.mEdgeCount = 1;

    marcher.March(QuadsSSBO, GlyphsSSBO, CameraUBO.mQuadsCount, CameraUBO.mGlyphsCount, CameraUBO.mPerspectiveFar);
    oFragColor.* = marcher.GenerateColor(ShadingSSBO);
}

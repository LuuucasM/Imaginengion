const std = @import("std");
const SDFShared = @import("SDFSharedData.zig");
const spirv = std.spirv;

const Vec2 = @import("IM").Vec2;
const Vec3 = @import("IM").Vec3;
const Vec4 = @import("IM").Vec4;

const RayMarcher = @import("IM").RayMarcher;

const CameraUBO = SDFShared.CameraUBO;
const QuadsSSBO = SDFShared.QuadsSSBO;
const GlyphsSSBO = SDFShared.GlyphsSSBO;
const ShadingSSBO = SDFShared.ShadingSSBO;
const OutTexture = SDFShared.OutTexture;
const TexturesArray = SDFShared.TexturesArray;

const imageRead = SDFShared.imageRead;

const default_color = Vec4(f32){ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 };

export fn main() callconv(.{ .spirv_kernel = .{ .x = 8, .y = 8, .z = 1 } }) void {
    const global = spirv.global_invocation_id;
    if (global[0] >= CameraUBO.mViewportWidth or global[1] >= CameraUBO.mViewportHeight) return;

    const sample = imageRead(OutTexture, u32, .{ global[0], global[1] });
    if (sample.w >= 0.999) return;

    const frag: @Vector(2, f32) = @Vector(2, f32){ @as(f32, @floatFromInt(global[0])) + 0.5, @as(f32, @floatFromInt(global[1])) + 0.5 };

    const uv = Vec2(f32).FromVector(CameraUBO.mRayScale).MulVec(Vec2(f32){ .x = frag[0], .y = frag[1] }).AddVec(Vec2(f32).FromVector(CameraUBO.mRayOffset));

    const dir = Vec3(f32).Dir(.{ .x = uv.x, .y = uv.y, .z = -1.0 });
    const ray_dir = dir.QuatRotate(.FromVector(CameraUBO.mRotation));

    var marcher = RayMarcher{
        .mNodes = undefined,
        .mEdges = undefined,
        .mNodeCount = 0,
        .mEdgeCount = 0,
        .mDefaultColor = default_color,
    };

    //setup initial node and edge
    marcher.mNodes[0] = RayMarcher.Node{
        .Point = .FromVector(CameraUBO.mPosition),
        .Normal = .{ .x = 0, .y = 0, .z = 0 },
        .ParentEdge = RayMarcher.NO_EDGE,
        .FirstEdge = RayMarcher.NO_EDGE,
        .MaterialHandle = 0,
        .AccumColor = default_color,
        .TextureUV = .{ .x = 0, .y = 0 },
        .ShapeT = .None,
    };
    marcher.mNodeCount = 1;

    marcher.mEdges[0] = RayMarcher.Edge{
        .Direction = ray_dir,
        .Length = 0.0,
        .FromNode = 0,
        .ToNode = 0,
        .SiblingEdge = RayMarcher.NO_EDGE,
        .AccumColor = default_color,
        .MaterialHandle = 0,
    };
    marcher.mNodes[0].FirstEdge = 0;
    marcher.mEdgeCount = 1;

    marcher.March(QuadsSSBO.ptr, GlyphsSSBO.ptr, CameraUBO.mPerspectiveFar, std.spirv.imageSampleImplicitLod);

    //traverse ray tree backwards to obtain final output color
    const march_color = marcher.GenerateColor(ShadingSSBO.ptr, TexturesArray, std.spirv.imageSampleImplicitLod);

    const out_a = march_color.w + sample.w * (1.0 - march_color.w);

    const out_rgb = if (out_a > 0) march_color.ToVec3().MulScalar(march_color.w).AddVec(sample.ToVec3().MulScalar(sample.w * (1.0 - march_color.w))).DivScalar(out_a) else Vec3(f32){ .x = 0, .y = 0, .z = 0 };

    const final_color = Vec4(f32){ out_rgb.x, out_rgb.y, out_rgb.z, out_a };

    std.spirv.imageWrite(OutTexture, u32, .{ global[0], global[1] }, final_color.ToVector());
}

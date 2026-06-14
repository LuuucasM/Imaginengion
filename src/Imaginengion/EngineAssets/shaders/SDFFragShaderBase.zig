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

pub const Image2D = @SpirvType(
    .{ .image = .{
        .usage = .{ .sampled = f32 },
        .format = .unknown,
        .dim = .@"2d",
        .depth = .not_depth,
        .access = .unknown,
        .arrayed = true,
        .multisampled = false,
    } },
);

pub const Sampler2D = @SpirvType(.{ .sampled_image = Image2D });

//std.lang.Type.Spirv

pub fn FragShaderBase(
    oFragColor: *addrspace(.output) @Vector(4, f32),
    CameraUBO: *addrspace(.uniform) PushConstants,
    QuadsSSBO: [*]addrspace(.storage_buffer) QuadData,
    GlyphsSSBO: [*]addrspace(.storage_buffer) GlyphData,
    ShadingSSBO: [*]addrspace(.storage_buffer) ShadingData,
    Textures: *addrspace(.constant) Sampler2D,
) void {
    _ = Textures;
    const frag = gpu.frag_coord;

    const uv = Vec2(f32).FromVector(CameraUBO.mRayScale).MulVec(Vec2(f32){ .x = frag[0], .y = frag[1] }).AddVec(Vec2(f32).FromVector(CameraUBO.mRayOffset));

    const dir = Vec3(f32).Dir(.{ .x = uv.x, .y = uv.y, .z = -1.0 });
    const ray_dir = dir.QuatRotate(.FromVector(CameraUBO.mRotation));

    var marcher = RayMarcher{
        .mNodes = undefined,
        .mEdges = undefined,
        .mNodeCount = 0,
        .mEdgeCount = 0,
    };

    //setup initial node and edge
    marcher.mNodes[0] = RayMarcher.Node{
        .Point = .FromVector(CameraUBO.mPosition),
        .Normal = .{ .x = 0, .y = 0, .z = 0 },
        .ParentEdge = -1,
        .FirstEdge = -1,
        .MaterialHandle = 0,
        .AccumColor = RayMarcher.DEFAULT_COLOR,
        .TextureUV = .{ .x = 0, .y = 0 },
        .ShapeT = .None,
    };
    marcher.mNodeCount = 1;

    marcher.mEdges[0] = RayMarcher.Edge{
        .Direction = ray_dir,
        .Length = 0.0,
        .FromNode = 0,
        .ToNode = 0,
        .SiblingEdge = -1,
        .AccumColor = RayMarcher.DEFAULT_COLOR,
    };
    marcher.mNodes[0].FirstEdge = 0;
    marcher.mEdgeCount = 1;

    marcher.March(QuadsSSBO, GlyphsSSBO, CameraUBO.mQuadsCount, CameraUBO.mGlyphsCount, CameraUBO.mPerspectiveFar);
    oFragColor.* = marcher.GenerateColor(ShadingSSBO);
}

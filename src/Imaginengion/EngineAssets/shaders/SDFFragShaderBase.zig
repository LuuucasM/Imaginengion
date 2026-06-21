const std = @import("std");
const spirv = std.spirv;

const PushConstants = @import("IM").PushConstants;
const QuadData = @import("IM").QuadData;
const GlyphData = @import("IM").GlyphData;
const ShadingData = @import("IM").ShadingData;
const RayMarcher = @import("IM").RayMarcher;
const Vec2 = @import("IM").Vec2;
const Vec3 = @import("IM").Vec3;
const Vec4 = @import("IM").Vec4;
const Quat = @import("IM").Quat;
const NO_EDGE = RayMarcher.NO_EDGE;

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

pub const QuadsSSBOT = @SpirvType(.{ .runtime_array = QuadData });

pub const Sampler2D = @SpirvType(.{ .sampled_image = Image2D });

pub const CameraUBO = @extern(*addrspace(.uniform) PushConstants, .{ .name = "CameraUBO", .decoration = .{ .descriptor = .{ .set = 3, .binding = 0 } } });

//layout(set = 2, binding = 0) uniform sampler2DArray uTextures;
pub const Textures = @extern(*addrspace(.constant) Sampler2D, .{ .name = "Textures", .decoration = .{ .descriptor = .{ .set = 2, .binding = 0 } } });
//layout(set = 2, binding = 1) uniform sampler
pub const Overlay = @extern(*addrspace(.constant) @SpirvType(.sampler), .{ .name = "Overlay", .decoration = .{ .descriptor = .{ .set = 2, .binding = 1 } } });

//layout(set = 2, binding = 2) readonly buffer QuadsSSBO { QuadData data[]; } Quads;
//pub const QuadsSSBO = @extern(*addrspace(.storage_buffer) QuadData, .{ .name = "QuadsSSBO", .decoration = .{ .descriptor = .{ .set = 2, .binding = 2 } } });
pub const QuadsSSBO = @extern(*addrspace(.storage_buffer) QuadData, .{ .name = "QuadsSSBO", .decoration = .{ .descriptor = .{ .set = 2, .binding = 2 } } });

//layout(set = 2, binding = 3) readonly buffer GlyphSSBO { GlyphData data[]; } Glyphs;
pub const GlyphsSSBO = @extern(*addrspace(.storage_buffer) GlyphData, .{ .name = "GlyphsSSBO", .decoration = .{ .descriptor = .{ .set = 2, .binding = 3 } } });

//layout(set = 2, binding = 4) readonly buffer ShadingSSBO { ShadingData data[]; } Shading;
pub const ShadingSSBO = @extern(*addrspace(.storage_buffer) ShadingData, .{ .name = "ShadingSSBO", .decoration = .{ .descriptor = .{ .set = 2, .binding = 4 } } });

pub fn FragShaderBase(
    camera_ubo: PushConstants,
    quads_ssbo: [*]QuadData,
    glyphs_ssbo: [*]GlyphData,
    shading_ssbo: [*]ShadingData,
    textures: *addrspace(.constant) Sampler2D,
) @Vector(4, f32) {
    _ = textures;
    const frag = spirv.frag_coord;

    const uv = Vec2(f32).FromVector(camera_ubo.mRayScale).MulVec(Vec2(f32){ .x = frag[0], .y = frag[1] }).AddVec(Vec2(f32).FromVector(camera_ubo.mRayOffset));

    const dir = Vec3(f32).Dir(.{ .x = uv.x, .y = uv.y, .z = -1.0 });
    const ray_dir = dir.QuatRotate(.FromVector(camera_ubo.mRotation));

    var marcher = RayMarcher{
        .mNodes = undefined,
        .mEdges = undefined,
        .mNodeCount = 0,
        .mEdgeCount = 0,
    };

    //setup initial node and edge
    marcher.mNodes[0] = RayMarcher.Node{
        .Point = .FromVector(camera_ubo.mPosition),
        .Normal = .{ .x = 0, .y = 0, .z = 0 },
        .ParentEdge = NO_EDGE,
        .FirstEdge = NO_EDGE,
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
        .SiblingEdge = NO_EDGE,
        .AccumColor = RayMarcher.DEFAULT_COLOR,
    };
    marcher.mNodes[0].FirstEdge = 0;
    marcher.mEdgeCount = 1;

    //create the ray tree
    marcher.March(quads_ssbo.*[0..camera_ubo.mQuadsCount], glyphs_ssbo.*[9..camera_ubo.mGlyphsCount], camera_ubo.mPerspectiveFar);

    //traverse ray tree backwards to obtain final output color
    return marcher.GenerateColor(shading_ssbo.*);
}

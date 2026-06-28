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

pub const Image2DArray = @SpirvType(
    .{ .image = .{
        .usage = .{ .sampled = f32 },
        .format = .unknown,
        .dim = .@"2d",
        .depth = .unknown,
        .access = .unknown,
        .arrayed = true,
        .multisampled = false,
    } },
);

pub const Image2D = @SpirvType(
    .{ .image = .{
        .usage = .{ .sampled = f32 },
        .dim = .@"2d",
        .format = .unknown,
        .depth = .unknown,
        .access = .unknown,
        .arrayed = false,
        .multisampled = false,
    } },
);

pub const oFragColor = @extern(*addrspace(.output) @Vector(4, f32), .{
    .name = "oFragColor",
    .decoration = .{ .location = 0 },
});

pub const QuadsSSBOT = @SpirvType(.{ .runtime_array = QuadData });

pub const Sampler2DArray = @SpirvType(.{ .sampled_image = Image2DArray });

pub const Sampler2D = @SpirvType(.{ .sampled_image = Image2D });

pub const CameraUBO = @extern(*addrspace(.uniform) PushConstants, .{ .name = "CameraUBO", .decoration = .{ .descriptor = .{ .set = 3, .binding = 0 } } });

//layout(set = 2, binding = 0) uniform sampler2DArray uTextures;
pub const TexturesArray = @extern(*addrspace(.constant) Sampler2DArray, .{ .name = "Textures", .decoration = .{ .descriptor = .{ .set = 2, .binding = 0 } } });
//layout(set = 2, binding = 1) uniform sampler
pub const Overlay = @extern(*addrspace(.constant) Sampler2D, .{ .name = "Overlay", .decoration = .{ .descriptor = .{ .set = 2, .binding = 1 } } });

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
    textures: *addrspace(.constant) Sampler2DArray,
) @Vector(4, f32) {
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
    marcher.March(quads_ssbo.*[0..camera_ubo.mQuadsCount], glyphs_ssbo.*[9..camera_ubo.mGlyphsCount], camera_ubo.mPerspectiveFar, SampleSampler);

    //traverse ray tree backwards to obtain final output color
    return marcher.GenerateColor(shading_ssbo.*, textures, SampleSampler);
}

pub fn SampleSampler(comptime deco: std.builtin.ExternOptions.Decoration, uv_layer: Vec3(f32)) Vec4(f32) {
    return asm volatile (
        \\%sampler_ptr    = OpTypePointer UniformConstant %ty
        \\%tex            = OpVariable %sampler_ptr UniformConstant
        \\                  OpDecorate %tex DescriptorSet $set
        \\                  OpDecorate %tex Binding $bind
        \\%loaded_sampler = OpLoad %ty %tex
        \\%ret            = OpImageSampleImplicitLod %v4 %loaded_sampler %uv_layer
        : [ret] "" (-> Vec4),
        : [uv_layer] "" (uv_layer),
          [ty] "t" (Sampler2DArray),
          [v4] "t" (Vec4),
          [set] "c" (deco.descriptor.set),
          [bind] "c" (deco.descriptor.binding),
    );
}

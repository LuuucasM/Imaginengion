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

pub const Sampler2DArray = @SpirvType(.{ .sampled_image = Image2DArray });

pub const Sampler2D = @SpirvType(.{ .sampled_image = Image2D });

const QuadsArray = @SpirvType(.{ .runtime_array = QuadData });
pub const QuadsBuf = extern struct { ptr: QuadsArray };

const GlyphsArray = @SpirvType(.{ .runtime_array = GlyphData });
pub const GlyphsBuf = extern struct { ptr: GlyphsArray };

const ShadingArray = @SpirvType(.{ .runtime_array = ShadingData });
pub const ShadingBuf = extern struct { ptr: ShadingArray };

pub const CameraUBO = @extern(*addrspace(.uniform) PushConstants, .{ .name = "CameraUBO", .decoration = .{ .descriptor = .{ .set = 3, .binding = 0 } } });

//layout(set = 2, binding = 0) uniform sampler2DArray uTextures;
pub const TexturesArray = @extern(*addrspace(.constant) Sampler2DArray, .{ .name = "Textures", .decoration = .{ .descriptor = .{ .set = 2, .binding = 0 } } });
//layout(set = 2, binding = 1) uniform sampler
pub const Overlay = @extern(*addrspace(.constant) Sampler2D, .{ .name = "Overlay", .decoration = .{ .descriptor = .{ .set = 2, .binding = 1 } } });

//layout(set = 2, binding = 2) readonly buffer QuadsSSBO { QuadData data[]; } Quads;
//pub const QuadsSSBO = @extern(*addrspace(.storage_buffer) QuadData, .{ .name = "QuadsSSBO", .decoration = .{ .descriptor = .{ .set = 2, .binding = 2 } } });
pub const QuadsSSBO = @extern(*addrspace(.storage_buffer) QuadsBuf, .{ .name = "QuadsSSBO", .decoration = .{ .descriptor = .{ .set = 2, .binding = 2 } } });

//layout(set = 2, binding = 3) readonly buffer GlyphSSBO { GlyphData data[]; } Glyphs;
pub const GlyphsSSBO = @extern(*addrspace(.storage_buffer) GlyphsBuf, .{ .name = "GlyphsSSBO", .decoration = .{ .descriptor = .{ .set = 2, .binding = 3 } } });

//layout(set = 2, binding = 4) readonly buffer ShadingSSBO { ShadingData data[]; } Shading;
pub const ShadingSSBO = @extern(*addrspace(.storage_buffer) ShadingBuf, .{ .name = "ShadingSSBO", .decoration = .{ .descriptor = .{ .set = 2, .binding = 4 } } });

pub fn FragShaderBase(
    camera_ubo: PushConstants,
    quads_ssbo: anytype,
    glyphs_ssbo: anytype,
    shading_ssbo: anytype,
    textures: *addrspace(.constant) Sampler2DArray,
    default_color: Vec4(f32),
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
        .mDefaultColor = default_color,
    };

    //setup initial node and edge
    marcher.mNodes[0] = RayMarcher.Node{
        .Point = .FromVector(camera_ubo.mPosition),
        .Normal = .{ .x = 0, .y = 0, .z = 0 },
        .ParentEdge = NO_EDGE,
        .FirstEdge = NO_EDGE,
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
        .SiblingEdge = NO_EDGE,
        .AccumColor = default_color,
    };
    marcher.mNodes[0].FirstEdge = 0;
    marcher.mEdgeCount = 1;

    //create the ray tree
    marcher.March(quads_ssbo.ptr, glyphs_ssbo.ptr, camera_ubo.mPerspectiveFar, SampleSampler);

    //traverse ray tree backwards to obtain final output color
    return marcher.GenerateColor(shading_ssbo.ptr, textures, SampleSampler);
}

pub fn SampleSampler(comptime deco: std.builtin.ExternOptions.Decoration, uv_layer: Vec3(f32).VectorT) Vec4(f32).VectorT {
    return asm volatile (
        \\%sampler_ptr    = OpTypePointer UniformConstant %ty
        \\%tex            = OpVariable %sampler_ptr UniformConstant
        \\                  OpDecorate %tex DescriptorSet $set
        \\                  OpDecorate %tex Binding $bind
        \\%loaded_sampler = OpLoad %ty %tex
        \\%ret            = OpImageSampleImplicitLod %v4 %loaded_sampler %uv_layer
        : [ret] "" (-> Vec4(f32).VectorT),
        : [uv_layer] "" (uv_layer),
          [ty] "t" (Sampler2DArray),
          [v4] "t" (Vec4(f32).VectorT),
          [set] "c" (deco.descriptor.set),
          [bind] "c" (deco.descriptor.binding),
    );
}

pub fn SampleTexture(comptime deco: std.builtin.ExternOptions.Decoration, uv_layer: Vec2(f32).VectorT) Vec4(f32).VectorT {
    return asm volatile (
        \\%sampler_ptr    = OpTypePointer UniformConstant %ty
        \\%tex            = OpVariable %sampler_ptr UniformConstant
        \\                  OpDecorate %tex DescriptorSet $set
        \\                  OpDecorate %tex Binding $bind
        \\%loaded_sampler = OpLoad %ty %tex
        \\%ret            = OpImageSampleImplicitLod %v4 %loaded_sampler %uv_layer
        : [ret] "" (-> Vec4(f32).VectorT),
        : [uv_layer] "" (uv_layer),
          [ty] "t" (Sampler2D),
          [v4] "t" (Vec4(f32).VectorT),
          [set] "c" (deco.descriptor.set),
          [bind] "c" (deco.descriptor.binding),
    );
}

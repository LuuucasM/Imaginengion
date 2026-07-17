const std = @import("std");
const PushConstants = @import("IM").PushConstants;
const QuadData = @import("IM").QuadData;
const GlyphData = @import("IM").GlyphData;
const SurfShadingData = @import("IM").SurfShadingData;
const MedShadingData = @import("IM").MedShadingData;
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

const SurfShadingArray = @SpirvType(.{ .runtime_array = SurfShadingData });
pub const SurfShadingBuf = extern struct { ptr: SurfShadingArray };

const MedShadingArray = @SpirvType(.{ .runtime_array = MedShadingData });
pub const MedShadingBuf = extern struct { ptr: MedShadingArray };

pub const CameraUBO = @extern(*addrspace(.uniform) PushConstants, .{ .name = "CameraUBO", .decoration = .{ .descriptor = .{ .set = 3, .binding = 0 } } });

//layout(set = 2, binding = 0) uniform sampler2DArray uTextures;
pub const TexturesArray = @extern(*addrspace(.constant) Sampler2DArray, .{ .name = "Textures", .decoration = .{ .descriptor = .{ .set = 2, .binding = 0 } } });
//layout(set = 2, binding = 1) uniform sampler
pub const OutTexture = @extern(*addrspace(.constant) Sampler2D, .{ .name = "OutTexture", .decoration = .{ .descriptor = .{ .set = 2, .binding = 1 } } });

//layout(set = 2, binding = 2) readonly buffer ShadingSSBO { ShadingData data[]; } Shading;
pub const SurfShadingSSBO = @extern(*addrspace(.storage_buffer) SurfShadingBuf, .{ .name = "ShadingSSBO", .decoration = .{ .descriptor = .{ .set = 2, .binding = 2 } } });

//layout(set = 2, binding = 3) readonly buffer ShadingSSBO { ShadingData data[]; } Shading;
pub const MedShadingSSBO = @extern(*addrspace(.storage_buffer) SurfShadingBuf, .{ .name = "ShadingSSBO", .decoration = .{ .descriptor = .{ .set = 2, .binding = 3 } } });

//layout(set = 2, binding = 4) readonly buffer QuadsSSBO { QuadData data[]; } Quads;
pub const QuadsSSBO = @extern(*addrspace(.storage_buffer) QuadsBuf, .{ .name = "QuadsSSBO", .decoration = .{ .descriptor = .{ .set = 2, .binding = 4 } } });

//layout(set = 2, binding = 5) readonly buffer GlyphSSBO { GlyphData data[]; } Glyphs;
pub const GlyphsSSBO = @extern(*addrspace(.storage_buffer) GlyphsBuf, .{ .name = "GlyphsSSBO", .decoration = .{ .descriptor = .{ .set = 2, .binding = 5 } } });

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

pub fn LoadTexturePixel(
    comptime deco: std.builtin.ExternOptions.Decoration,
    pixel: @Vector(2, i32),
) Vec4(f32).VectorT {
    return asm volatile (
        \\%image_ptr = OpTypePointer UniformConstant %ty 
        \\%image = OpVariable %image_ptr UniformConstant 
        \\ OpDecorate %image DescriptorSet $set 
        \\ OpDecorate %image Binding $bind 
        \\%loaded_image = OpLoad %ty %image 
        \\%ret = OpImageRead %v4 %loaded_image %pixel 
        : [ret] "" (-> Vec4(f32).VectorT),
        : [pixel] "" (pixel),
          [ty] "t" (Sampler2D),
          [v4] "t" (Vec4(f32).VectorT),
          [set] "c" (deco.descriptor.set),
          [bind] "c" (deco.descriptor.binding),
    );
}

pub fn StoreTexturePixel(
    comptime deco: std.builtin.ExternOptions.Decoration,
    pixel: @Vector(2, i32),
    color: Vec4(f32).VectorT,
) void {
    asm volatile (
        \\%image_ptr = OpTypePointer UniformConstant %ty 
        \\%image = OpVariable %image_ptr UniformConstant 
        \\ OpDecorate %image DescriptorSet $set 
        \\ OpDecorate %image Binding $bind 
        \\%loaded_image = OpLoad %ty %image 
        \\ OpImageWrite %loaded_image %pixel %color 
        :
        : [pixel] "" (pixel),
          [color] "" (color),
          [ty] "t" (Sampler2D),
          [set] "c" (deco.descriptor.set),
          [bind] "c" (deco.descriptor.binding),
    );
}

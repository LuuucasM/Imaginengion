const std = @import("std");
const builtin = @import("builtin");
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
        .format = .rgba8unorm,
        .dim = .@"2d",
        .depth = .unknown,
        .access = .unknown,
        .arrayed = true,
        .multisampled = false,
    } },
);

//std.lang.Type.Spirv

pub const Image2D = @SpirvType(
    .{ .image = .{
        .usage = .{ .storage = f32 },
        .dim = .@"2d",
        .format = .rgba8unorm,
        .depth = .unknown,
        .access = .unknown,
        .arrayed = false,
        .multisampled = false,
    } },
);

pub const Sampler2DArray = @SpirvType(.{ .sampled_image = Image2DArray });

const QuadsArray = @SpirvType(.{ .runtime_array = QuadData });
pub const QuadsBuf = extern struct { ptr: QuadsArray };

const GlyphsArray = @SpirvType(.{ .runtime_array = GlyphData });
pub const GlyphsBuf = extern struct { ptr: GlyphsArray };

const SurfShadingArray = @SpirvType(.{ .runtime_array = SurfShadingData });
pub const SurfShadingBuf = extern struct { ptr: SurfShadingArray };

const MedShadingArray = @SpirvType(.{ .runtime_array = MedShadingData });
pub const MedShadingBuf = extern struct { ptr: MedShadingArray };

pub const TexturesArray = @extern(*addrspace(.constant) Sampler2DArray, .{ .name = "Textures", .decoration = .{ .descriptor = .{ .set = 0, .binding = 0 } } });

pub const SurfShadingSSBO = @extern(*addrspace(.storage_buffer) SurfShadingBuf, .{ .name = "ShadingSSBO", .decoration = .{ .descriptor = .{ .set = 0, .binding = 1 } } });
pub const MedShadingSSBO = @extern(*addrspace(.storage_buffer) MedShadingBuf, .{ .name = "ShadingSSBO", .decoration = .{ .descriptor = .{ .set = 0, .binding = 2 } } });
pub const QuadsSSBO = @extern(*addrspace(.storage_buffer) QuadsBuf, .{ .name = "QuadsSSBO", .decoration = .{ .descriptor = .{ .set = 0, .binding = 3 } } });
pub const GlyphsSSBO = @extern(*addrspace(.storage_buffer) GlyphsBuf, .{ .name = "GlyphsSSBO", .decoration = .{ .descriptor = .{ .set = 0, .binding = 4 } } });

pub const OutTexture = @extern(*addrspace(.constant) Image2D, .{ .name = "OutTexture", .decoration = .{ .descriptor = .{ .set = 1, .binding = 0 } } });

pub const CameraUBO = @extern(*addrspace(.uniform) PushConstants, .{ .name = "CameraUBO", .decoration = .{ .descriptor = .{ .set = 2, .binding = 0 } } });

/// Read a texel from an image without a sampler.
/// The type of `image` must be a pointer to a SPIR-V image.
pub fn imageRead(
    image: anytype,
    T: type,
    coordinate: ImageCoordinate(std.meta.Child(@TypeOf(image)), T),
) @Vector(4, ImageSampledType(std.meta.Child(@TypeOf(image)))) {
    switch (T) {
        u32, i32 => {},
        f32 => if (builtin.target.os.tag != .opencl) {
            @compileError("Floating point image coordinates only supported by OpenCL");
        },
        else => @compileError("Expected one of u32, i32 and f32 types. Found '" ++ @typeName(T) ++ "'"),
    }
    const Image = switch (@typeInfo(@TypeOf(image))) {
        .pointer => |pointer| pointer.child,
        else => @compileError("Expected a pointer to SPIR-V image type, found '" ++ @typeName(@TypeOf(image)) ++ "'"),
    };
    const image_info = switch (@typeInfo(Image)) {
        .spirv => |spirv| switch (spirv) {
            .image => |info| info,
            else => @compileError("Expected SPIR-V image type, found '" ++ @typeName(Image) ++ "'"),
        },
        else => @compileError("Expected SPIR-V image type, found '" ++ @typeName(Image) ++ "'"),
    };
    switch (image_info.usage) {
        .unknown, .storage => {},
        else => @compileError("SPIR-V image must have unknown or storage usage"),
    }
    const Result = @Vector(4, ImageSampledType(Image));
    return asm volatile (
        \\%loaded_image = OpLoad %Image %image
        \\%ret           = OpImageRead %Result %loaded_image %coordinate
        : [ret] "" (-> Result),
        : [Image] "t" (Image),
          [image] "" (image),
          [Result] "t" (Result),
          [coordinate] "" (coordinate),
    );
}

/// The type of `sampled_image` must be a pointer to a SPIR-V sampled image.
pub fn imageSampleExplicitLod(
    sampled_image: anytype,
    coordinate: ImageCoordinate(std.meta.Child(@TypeOf(sampled_image)), f32),
    lod: f32,
) @Vector(4, ImageSampledType(std.meta.Child(@TypeOf(sampled_image)))) {
    const SampledImage = switch (@typeInfo(@TypeOf(sampled_image))) {
        .pointer => |pointer| pointer.child,
        else => @compileError("Expected a pointer to SPIR-V sampled image type, found '" ++ @typeName(@TypeOf(sampled_image)) ++ "'"),
    };
    const Result = @Vector(4, ImageSampledType(SampledImage));

    const image_info = switch (@typeInfo(SampledImage)) {
        .spirv => |spirv| switch (spirv) {
            .sampled_image => |sampled_image_info| @typeInfo(sampled_image_info).spirv.image,
            else => @compileError("Expected SPIR-V sampled image type, found '" ++ @typeName(SampledImage) ++ "'"),
        },
        else => @compileError("Expected SPIR-V sampled image type, found '" ++ @typeName(SampledImage) ++ "'"),
    };

    if (image_info.multisampled)
        @compileError("Can not explicitly sample a sampled image that was multisampled");

    // TOOD: If buffer dim is added, throw a compile error if the dimension is a buffer.

    return asm volatile (
        \\%loaded_sampler = OpLoad %SampledImage %sampled_image
        \\%ret            = OpImageSampleExplicitLod %Result %loaded_sampler %coordinate Lod %lod
        : [ret] "" (-> Result),
        : [SampledImage] "t" (SampledImage),
          [sampled_image] "" (sampled_image),
          [Result] "t" (Result),
          [coordinate] "" (coordinate),
          [lod] "" (lod),
    );
}

fn ImageCoordinate(Image: type, Element: type) type {
    const image_info = switch (@typeInfo(Image)) {
        .spirv => |spirv| switch (spirv) {
            .sampled_image => |sampled_image| @typeInfo(sampled_image).spirv.image,
            .image => |image| image,
            else => @compileError("Expected SPIR-V image or sampled image type, found '" ++ @typeName(Image) ++ "'"),
        },
        else => @compileError("Expected SPIR-V image or sampled image type, found '" ++ @typeName(Image) ++ "'"),
    };
    const dim = switch (image_info.dim) {
        .@"1d" => 1 + @as(u8, @intFromBool(image_info.arrayed)),
        .@"2d" => 2 + @as(u8, @intFromBool(image_info.arrayed)),
        .@"3d", .cube => 3 + @as(u8, @intFromBool(image_info.arrayed)),
    };
    if (dim == 1) return Element else return @Vector(dim, Element);
}

/// The type of the components that result from sampling or reading from the given SPIR-V image or sampled image type.
fn ImageSampledType(Image: type) type {
    const image_info = switch (@typeInfo(Image)) {
        .spirv => |spirv| switch (spirv) {
            .sampled_image => |sampled_image| @typeInfo(sampled_image).spirv.image,
            .image => |image| image,
            else => @compileError("Expected SPIR-V image or sampled image type, found '" ++ @typeName(Image) ++ "'"),
        },
        else => @compileError("Expected SPIR-V image or sampled image type, found '" ++ @typeName(Image) ++ "'"),
    };
    return switch (image_info.usage) {
        inline else => |usage| usage,
    };
}

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
pub const OutTexture = @extern(*addrspace(.constant) Image2D, .{ .name = "OutTexture", .decoration = .{ .descriptor = .{ .set = 2, .binding = 1 } } });

//layout(set = 2, binding = 2) readonly buffer ShadingSSBO { ShadingData data[]; } Shading;
pub const SurfShadingSSBO = @extern(*addrspace(.storage_buffer) SurfShadingBuf, .{ .name = "ShadingSSBO", .decoration = .{ .descriptor = .{ .set = 2, .binding = 2 } } });

//layout(set = 2, binding = 3) readonly buffer ShadingSSBO { ShadingData data[]; } Shading;
pub const MedShadingSSBO = @extern(*addrspace(.storage_buffer) SurfShadingBuf, .{ .name = "ShadingSSBO", .decoration = .{ .descriptor = .{ .set = 2, .binding = 3 } } });

//layout(set = 2, binding = 4) readonly buffer QuadsSSBO { QuadData data[]; } Quads;
pub const QuadsSSBO = @extern(*addrspace(.storage_buffer) QuadsBuf, .{ .name = "QuadsSSBO", .decoration = .{ .descriptor = .{ .set = 2, .binding = 4 } } });

//layout(set = 2, binding = 5) readonly buffer GlyphSSBO { GlyphData data[]; } Glyphs;
pub const GlyphsSSBO = @extern(*addrspace(.storage_buffer) GlyphsBuf, .{ .name = "GlyphsSSBO", .decoration = .{ .descriptor = .{ .set = 2, .binding = 5 } } });

/// Read a texel from an image without a sampler.
/// The type of `image` must be a pointer to a SPIR-V image.
pub fn imageRead(
    image: anytype,
    T: type,
    coordinate: std.spirv.ImageCoordinate(std.meta.Child(@TypeOf(image)), T),
) @Vector(4, std.spirv.ImageSampledType(std.meta.Child(@TypeOf(image)))) {
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
    const Result = @Vector(4, std.spirv.ImageSampledType(Image));
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

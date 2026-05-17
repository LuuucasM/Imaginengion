const std = @import("std");
const gpu = std.gpu;

const PushConstants = @import("../../src/Imaginengion/Renderer/RenderPipeline.zig").PushConstants;
const QuadData = @import("../../src/Imaginengion/Renderer/Renderer2D.zig").QuadData;
const GlyphData = @import("../../src/Imaginengion/Renderer/Renderer2D.zig").GlyphData;
const LinAlg = @import("../../src/Imaginengion/Math/LinAlg.zig");
const RayMarcher = @import("SDFRayMarcher.zig");

// layout(location = 0) out vec4 oFragColor
extern var oFragColor: @Vector(4, f32) addrspace(.output);

// layout(set = 3, binding = 0) uniform CameraUBO
extern const CameraUBO: PushConstants addrspace(.uniform);
extern var QuadsSSBO: [*]QuadData addrspace(.storage_buffer);
extern var GlyphsSSBO: [*]GlyphData addrspace(.storage_buffer);

export fn main() callconv(.spirv_fragment) void {
    gpu.location(&oFragColor, 0);
    gpu.binding(&CameraUBO, 3, 0);

    asm volatile (
        \\OpDecorate %q DescriptorSet 2
        \\OpDecorate %q Binding 1
        \\OpDecorate %q NonWritable
        \\OpDecorate %g DescriptorSet 2
        \\OpDecorate %g Binding 2
        \\OpDecorate %g NonWritable
        :
        : [q] "" (&QuadsSSBO),
          [g] "" (&GlyphsSSBO),
    );

    const frag = gpu.frag_coord;

    const uv = @Vector(2, f32){
        CameraUBO.mRayScale * frag[0] + CameraUBO.mRayOffset[0],
        CameraUBO.mRayScale * frag[1] + CameraUBO.mRayOffset[1],
    };

    const dir = LinAlg.NormalizeVec(@Vector(3, f32){ uv[0], uv[1], -1.0 });
    const ray_dir = LinAlg.RotateVec3Quat(CameraUBO.mRotation, dir);

    const marcher = RayMarcher{
        .mQuads = QuadsSSBO[0..CameraUBO.mQuadsCount],
        .mGlyphs = GlyphsSSBO[0..CameraUBO.mGlyphsCount],
        .mRay = .{ .Origin = CameraUBO.mPosition, .Direction = ray_dir },
        .mPerspectiveFar = CameraUBO.mPerspectiveFar,
    };

    const hit = marcher.March();

    oFragColor = .{ 0.7, 0.7, 0.7, hit[3] };
}

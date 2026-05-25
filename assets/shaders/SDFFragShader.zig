const std = @import("std");
const gpu = std.gpu;

const PushConstants = @import("../../src/Imaginengion/Renderer/RenderPipeline.zig").PushConstants;
const QuadData = @import("../../src/Imaginengion/Renderer/Renderer2D.zig").QuadData;
const GlyphData = @import("../../src/Imaginengion/Renderer/Renderer2D.zig").GlyphData;
const RayMarcher = @import("../../src/Imaginengion/Renderer/SDFRayMarcher.zig");
const MathTypes = @import("../../src/Imaginengion/Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;
const Vec3 = MathTypes.Vec3;
const Quat = MathTypes.Quat;

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

    const uv = Vec2(f32).FromVector(CameraUBO.mRayScale).MulVec(Vec2(f32){ .x = frag[0], .y = frag[1] }).AddVec(Vec2(f32).FromVector(CameraUBO.mRayOffset));

    const dir = Vec3(f32).Dir(.{ .x = uv.x, .y = uv.y, .z = -1.0 });
    const ray_dir = dir.QuatRotate(Quat(f32).FromVector(CameraUBO.mRotation));

    var marcher = RayMarcher{
        .mQuads = QuadsSSBO[0..CameraUBO.mQuadsCount],
        .mGlyphs = GlyphsSSBO[0..CameraUBO.mGlyphsCount],
        .mRay = .{ .Origin = CameraUBO.mPosition, .Direction = ray_dir },
        .mPerspectiveFar = CameraUBO.mPerspectiveFar,
    };
    marcher.mNodes[0] = .{ .SurfaceColor = .{ .x = 0, .y = 0, .z = 0, .w = 0 }, .FirstRay = 0, .ParentRay = -1, .Is2D = false };
    marcher.mNodeCount = 1;
    marcher.mEdges[0] = .{ .Ray = .{ .Origin = CameraUBO.mPosition, .Direction = ray_dir }, .FromNode = 0, .SiblingNode = -1, .ToNode = -1, .Length = -1 };
    marcher.mEdgeCount = 1;

    marcher.March();

    oFragColor = marcher.GenerateColor();
}

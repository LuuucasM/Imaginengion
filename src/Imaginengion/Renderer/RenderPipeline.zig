const std = @import("std");
const builtin = @import("builtin");
const sdl = @import("../Core/CImports.zig").sdl;
const ShaderAsset = @import("../Assets/Assets.zig").ShaderAsset;
const TextureFormat = @import("../Assets/Assets.zig").Texture2D.TextureFormat;
const EngineContext = @import("../Core/EngineContext.zig");
const GPUAsserts = @import("../Core/GPUAsserts.zig");

const MathTypes = @import("../Math/MathTypes.zig");
const Vec4 = MathTypes.Vec4;
const Vec3 = MathTypes.Vec3;
const Vec2 = MathTypes.Vec2;

pub const PipelineConfig = struct {
    color_format: TextureFormat,
    enable_blend: bool = true,
};

pub const PipelineType = enum {
    GamePipeline,
    OverlayPipeline,
    //CustomShader, one day when i konw what to even do with this
};

const is_spirv = builtin.target.cpu.arch.isSpirV();

pub const SDFPushConstants = extern struct {
    mRotation: if (is_spirv) Vec4(f32).VectorT else Vec4(f32).ArrayT,
    mPosition: if (is_spirv) Vec3(f32).VectorT else Vec3(f32).ArrayT,
    mRayScale: if (is_spirv) Vec2(f32).VectorT else Vec2(f32).ArrayT align(16),
    mRayOffset: if (is_spirv) Vec2(f32).VectorT else Vec2(f32).ArrayT,
    mPerspectiveFar: f32,
    mQuadsCount: u32,
    mGlyphsCount: u32,
    mViewportWidth: f32,
    mViewportHeight: f32,
};

comptime {
    GPUAsserts.AssertGPULayout(SDFPushConstants);
}

pub fn Pipeline(pipeline_t: PipelineType) type {
    return switch (pipeline_t) {
        .GamePipeline => @import("backends/GamePipeline.zig"),
        .OverlayPipeline => @import("backends/OverlayPipeline.zig"),
        //.CustomShader =>
    };
}

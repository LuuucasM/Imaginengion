const std = @import("std");
const builtin = @import("builtin");
const sdl = @import("../Core/CImports.zig").sdl;
const ShaderAsset = @import("../Assets/Assets.zig").ShaderAsset;
const TextureFormat = @import("../Assets/Assets.zig").Texture2D.TextureFormat;
const EngineContext = @import("../Core/EngineContext.zig");

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

pub const SDFPushConstants = extern struct {
    mPosition: Vec3(f32).VectorT,
    mPerspectiveFar: f32,
    mRotation: Vec4(f32).VectorT,
    mRayScale: Vec2(f32).VectorT,
    mRayOffset: Vec2(f32).VectorT,
    mQuadsCount: u32,
    mGlyphsCount: u32,
    mViewportWidth: u32,
    mViewportHeight: u32,
};

pub fn Pipeline(pipeline_t: PipelineType) type {
    return switch (pipeline_t) {
        .GamePipeline => @import("backends/GamePipeline.zig"),
        .OverlayPipeline => @import("backends/OverlayPipeline.zig"),
        //.CustomShader =>
    };
}

const std = @import("std");
const builtin = @import("builtin");
const sdl = @import("../Core/CImports.zig").sdl;
const ShaderAsset = @import("../ECSComponents/AComponents.zig").ShaderAsset;
const TextureFormat = @import("../ECSComponents/AComponents.zig").Texture2D.TextureFormat;
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
    /// What a game layer ray that hits nothing ends on: the background behind everything. Also what the overlay pass
    /// goes under when the game pass is skipped (FLAG_GAME_BACKGROUND), and what the texture is cleared to when no pass runs
    pub const GAME_BACKGROUND = [4]f32{ 0.0, 0.28, 0.39, 1.0 };
    /// What an overlay ray that hits nothing ends on, so whatever is under the overlay shows through
    pub const OVERLAY_BACKGROUND = [4]f32{ 0.0, 0.0, 0.0, 0.0 };

    /// overlay pass: put GAME_BACKGROUND under what it drew, since the game layer's pass doesn't run
    pub const FLAG_GAME_BACKGROUND: u32 = 1 << 0;
    /// game pass: draw under what the overlay pass wrote, reading it first. Without it the texture holds nothing yet
    pub const FLAG_UNDER_OVERLAY: u32 = 1 << 1;

    mRotation: if (is_spirv) Vec4(f32).VectorT else Vec4(f32).ArrayT,
    mPosition: if (is_spirv) Vec3(f32).VectorT else Vec3(f32).ArrayT,
    mRayScale: if (is_spirv) Vec2(f32).VectorT else Vec2(f32).ArrayT align(16),
    mRayOffset: if (is_spirv) Vec2(f32).VectorT else Vec2(f32).ArrayT,
    mPerspectiveFar: f32,
    mShapesCount: u32,
    //the shapes before this are found with a ray test straight against them, the rest by marching (ShapeSort)
    mDirectCount: u32,
    mViewportWidth: f32,
    mViewportHeight: f32,
    //the FLAG_ bits, set per pass from the render's PassPlan
    mFlags: u32,
};

comptime {
    GPUAsserts.AssertGPULayout(SDFPushConstants);
}

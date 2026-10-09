const std = @import("std");
const sdl = @import("../../Core/CImports.zig").sdl;
const StorageBufferBinding = @import("../RenderPlatform.zig").StorageBufferBinding;
const PipelineConfig = @import("../RenderPipeline.zig").PipelineConfig;
const EngineContext = @import("../../Core/EngineContext.zig");
const ShaderAsset = @import("../../ECSComponents/AComponents.zig").ShaderAsset;
const StageInfo = ShaderAsset.StageInfo;
const Stage = ShaderAsset.Stage;
const TextureFormat = @import("../../ECSComponents/AComponents.zig").Texture2D.TextureFormat;
const PushConstants = @import("../RenderPipeline.zig").SDFPushConstants;
const PassPlan = @import("../PassPlan.zig");

const MathTypes = @import("../../Math/MathTypes.zig");
const Vec4 = MathTypes.Vec4;
const Vec3 = MathTypes.Vec3;
const Vec2 = MathTypes.Vec2;

pub const PipelineType = enum {
    Overlay,
    Game,
};

const ShaderInfo: StageInfo = .{
    .mNumSamplers = 1,
    .mNumROStorageTextures = 0,
    //surface shading, medium shading, shapes, shape surfaces, masks, the BVH's nodes, and the mask programs' instructions
    //and parts
    .mNumROStorageBuffers = 8,
    .mNumRWStorageTextures = 1,
    .mNumRWStorageBuffers = 0,
    .mNumUniformBuffers = 1,
    .mThreadCountX = 8,
    .mThreadCountY = 8,
    .mThreadCountZ = 1,
};

const Config: PipelineConfig = .{
    .color_format = .RGBA8,
    .enable_blend = true,
};

pub fn SDFPipeline(pipeline_type: PipelineType) type {
    return struct {
        //the shaders as this build compiled them (build_shaders.zig's anonymous imports), so they always match the CPU
        //side's structs. `zig build shaders` still writes copies to EngineAssets/shaders/ for inspecting
        const FullShader = switch (pipeline_type) {
            .Overlay => @embedFile("SDFComputeOverlay"),
            .Game => @embedFile("SDFComputeGame"),
        };
        //the same shader compiled with merges and marching left out (PassPlan.ShaderVariant)
        const LeanShader = switch (pipeline_type) {
            .Overlay => @embedFile("SDFComputeOverlayLean"),
            .Game => @embedFile("SDFComputeGameLean"),
        };

        const Self = @This();

        pub const empty: Self = .{
            .mFullPipeline = null,
            .mLeanPipeline = null,
        };

        mFullPipeline: ?*sdl.struct_SDL_GPUComputePipeline,
        mLeanPipeline: ?*sdl.struct_SDL_GPUComputePipeline,

        pub fn Init(self: *Self, engine_context: *EngineContext) !void {
            const device: *sdl.SDL_GPUDevice = @ptrCast(engine_context.mRenderer.mPlatform.GetDevice());
            self.mFullPipeline = try CreatePipeline(device, FullShader);
            self.mLeanPipeline = try CreatePipeline(device, LeanShader);
        }

        fn CreatePipeline(device: *sdl.SDL_GPUDevice, comptime shader: []const u8) !*sdl.struct_SDL_GPUComputePipeline {
            std.debug.assert(shader.len % 4 == 0);

            const create_info = sdl.SDL_GPUComputePipelineCreateInfo{
                .code_size = shader.len,
                .code = shader.ptr,
                .entrypoint = "main",
                .format = sdl.SDL_GPU_SHADERFORMAT_SPIRV,
                .num_samplers = ShaderInfo.mNumSamplers,
                .num_readonly_storage_textures = ShaderInfo.mNumROStorageTextures,
                .num_readonly_storage_buffers = ShaderInfo.mNumROStorageBuffers,
                .num_readwrite_storage_textures = ShaderInfo.mNumRWStorageTextures,
                .num_readwrite_storage_buffers = ShaderInfo.mNumRWStorageBuffers,
                .num_uniform_buffers = ShaderInfo.mNumUniformBuffers,
                .threadcount_x = ShaderInfo.mThreadCountX,
                .threadcount_y = ShaderInfo.mThreadCountY,
                .threadcount_z = ShaderInfo.mThreadCountZ,
                .props = 0,
            };

            return sdl.SDL_CreateGPUComputePipeline(device, &create_info) orelse {
                std.log.err("SDFPipeline({s}): failed to create — {s}", .{ @tagName(pipeline_type), sdl.SDL_GetError() });
                return error.PipelineInitFailed;
            };
        }

        pub fn Deinit(self: *Self, engine_context: *EngineContext) void {
            const device: *sdl.SDL_GPUDevice = @ptrCast(engine_context.mRenderer.mPlatform.GetDevice());
            _ = sdl.SDL_WaitForGPUIdle(device);
            if (self.mFullPipeline) |p| sdl.SDL_ReleaseGPUComputePipeline(device, p);
            if (self.mLeanPipeline) |p| sdl.SDL_ReleaseGPUComputePipeline(device, p);
            self.mFullPipeline = null;
            self.mLeanPipeline = null;
        }

        /// Binds the compile of the shader `variant` says: the lean one for a pass without merges or marched shapes
        pub fn Bind(self: Self, pass: *anyopaque, variant: PassPlan.ShaderVariant) void {
            const sdl_pass: *sdl.SDL_GPUComputePass = @ptrCast(pass);
            sdl.SDL_BindGPUComputePipeline(sdl_pass, switch (variant) {
                .Full => self.mFullPipeline,
                .Lean => self.mLeanPipeline,
            });
        }

        pub fn PushUniforms(_: Self, cmd: *anyopaque, push: PushConstants) void {
            const sdl_cmd: *sdl.SDL_GPUCommandBuffer = @ptrCast(cmd);

            sdl.SDL_PushGPUComputeUniformData(
                sdl_cmd,
                0,
                &push,
                @sizeOf(PushConstants),
            );
        }

        // group counts, not pixel counts — divide screen dims by threadcount, round up.
        pub fn Dispatch(_: Self, pass: *anyopaque, screen_w: u32, screen_h: u32) void {
            const sdl_pass: *sdl.SDL_GPUComputePass = @ptrCast(pass);
            const groups_x = (screen_w + ShaderInfo.mThreadCountX - 1) / ShaderInfo.mThreadCountX;
            const groups_y = (screen_h + ShaderInfo.mThreadCountY - 1) / ShaderInfo.mThreadCountY;
            sdl.SDL_DispatchGPUCompute(sdl_pass, groups_x, groups_y, 1);
        }
    };
}

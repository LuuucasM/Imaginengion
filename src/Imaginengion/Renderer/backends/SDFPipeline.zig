const std = @import("std");
const sdl = @import("../../Core/CImports.zig").sdl;
const StorageBufferBinding = @import("../RenderPlatform.zig").StorageBufferBinding;
const PipelineConfig = @import("../RenderPipeline.zig").PipelineConfig;
const EngineContext = @import("../../Core/EngineContext.zig");
const ShaderAsset = @import("../../Assets/Assets.zig").ShaderAsset;
const StageInfo = ShaderAsset.StageInfo;
const Stage = ShaderAsset.Stage;
const TextureFormat = @import("../../Assets/Assets.zig").Texture2D.TextureFormat;
const PushConstants = @import("../RenderPipeline.zig").SDFPushConstants;

const MathTypes = @import("../../Math/MathTypes.zig");
const Vec4 = MathTypes.Vec4;
const Vec3 = MathTypes.Vec3;
const Vec2 = MathTypes.Vec2;

pub const PipelineType = enum {
    Overlay,
    Game,
};

pub fn SDFPipeline(pipeline_type: PipelineType) type {
    return struct {
        const ComputeShader = switch (pipeline_type) {
            .Overlay => @import("OverlayCompute"),
            .Game => @import("GameCompute"),
        };

        const ShaderInfo: StageInfo = .{
            .mNumSamplers = 2,
            .mNumROStorageTextures = 0,
            .mNumROStorageBuffers = 3,
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

        const Self = @This();

        pub const empty: Self = .{
            .mPipeline = null,
        };

        mPipeline: ?*sdl.SDL_GPUGraphicsPipeline,

        pub fn Init(self: *Self, engine_context: *EngineContext) !void {
            const device: *sdl.SDL_GPUDevice = @ptrCast(engine_context.mRenderer.mPlatform.GetDevice());

            std.debug.assert(ComputeShader.len % 4 == 0);
            const create_info = sdl.SDL_GPUComputePipelineCreateInfo{
                .code_size = ComputeShader.len,
                .code = ComputeShader.ptr,
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

            self.mPipeline = sdl.SDL_CreateGPUComputePipeline(device, &create_info) orelse {
                std.log.err("GameComputePipeline: failed to create — {s}", .{sdl.SDL_GetError()});
                return error.PipelineInitFailed;
            };
            std.log.info("GameComputePipeline: created successfully", .{});
        }

        pub fn Deinit(self: *Self, engine_context: *EngineContext) void {
            const device: *sdl.SDL_GPUDevice = @ptrCast(engine_context.mRenderer.mPlatform.GetDevice());
            _ = sdl.SDL_WaitForGPUIdle(device);
            if (self.mPipeline) |p| sdl.SDL_ReleaseGPUComputePipeline(device, p);
            self.mPipeline = null;
        }

        pub fn Begin(self: Self, cmd: *anyopaque, output_texture: *sdl.SDL_GPUTexture) *sdl.SDL_GPUComputePass {
            const sdl_cmd: *sdl.SDL_GPUCommandBuffer = @ptrCast(cmd);

            const storage_tex_binding = sdl.SDL_GPUStorageTextureReadWriteBinding{
                .texture = output_texture,
                .mip_level = 0,
                .layer = 0,
                .cycle = true,
            };

            const pass = sdl.SDL_BeginGPUComputePass(
                sdl_cmd,
                &storage_tex_binding,
                1,
                null, // no readwrite storage buffers
                0,
            ).?;

            sdl.SDL_BindGPUComputePipeline(pass, self.mPipeline);
            return pass;
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

        /// group counts, not pixel counts — divide screen dims by threadcount, round up.
        pub fn Dispatch(_: Self, pass: *sdl.SDL_GPUComputePass, screen_w: u32, screen_h: u32) void {
            const groups_x = (screen_w + ShaderInfo.mThreadCountX - 1) / ShaderInfo.mThreadCountX;
            const groups_y = (screen_h + ShaderInfo.mThreadCountY - 1) / ShaderInfo.mThreadCountY;
            sdl.SDL_DispatchGPUCompute(pass, groups_x, groups_y, 1);
        }

        pub fn End(_: Self, pass: *sdl.SDL_GPUComputePass) void {
            sdl.SDL_EndGPUComputePass(pass);
        }
    };
}

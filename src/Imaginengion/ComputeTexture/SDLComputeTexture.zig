const std = @import("std");
const TextureFormat = @import("../Assets/Assets.zig").Texture2D.TextureFormat;
const sdl = @import("../Core/CImports.zig").sdl;
const EngineContext = @import("../Core/EngineContext.zig");

pub fn SDLComputeStorageTexture(comptime format: TextureFormat) type {
    return struct {
        const Self = @This();

        pub const empty: Self = .{
            .mTexture = null,
            .mSampler = null,
            .mWidth = 0,
            .mHeight = 0,
        };

        mTexture: ?*sdl.SDL_GPUTexture,
        mSampler: ?*sdl.SDL_GPUSampler,
        mWidth: usize,
        mHeight: usize,

        pub fn Init(self: *Self, engine_context: *EngineContext, width: usize, height: usize) !void {
            self.mWidth = width;
            self.mHeight = height;
            try self.Create(engine_context);
        }

        pub fn Deinit(self: *Self, engine_context: *EngineContext) !void {
            try self.Destroy(engine_context);
        }

        pub fn Resize(self: *Self, engine_context: *EngineContext, width: usize, height: usize) !void {
            if (width < 1 or height < 1 or width > 8192 or height > 8192 or (width == self.mWidth and height == self.mHeight)) return;
            self.mWidth = width;
            self.mHeight = height;
            try self.Invalidate(engine_context);
        }

        pub fn Invalidate(self: *Self, engine_context: *EngineContext) !void {
            try self.Destroy(engine_context);
            try self.Create(engine_context);
        }

        /// Begins a compute pass with this texture bound read-write at slot 0.
        /// cycle: true for overlay pass (fresh write), false for game pass (must see overlay's writes).
        pub fn BeginComputePass(self: *Self, engine_context: *EngineContext, cycle: bool) *sdl.SDL_GPUComputePass {
            const cmd: *sdl.SDL_GPUCommandBuffer = @ptrCast(@alignCast(engine_context.mRenderer.mPlatform.GetCommandBuff()));

            const storage_tex_binding = sdl.SDL_GPUStorageTextureReadWriteBinding{
                .texture = self.mTexture.?,
                .mip_level = 0,
                .layer = 0,
                .cycle = cycle,
            };

            const pass = sdl.SDL_BeginGPUComputePass(
                cmd,
                &storage_tex_binding,
                1,
                null,
                0,
            );
            std.debug.assert(pass != null);
            return pass.?;
        }

        pub fn EndComputePass(_: Self, pass: *anyopaque) void {
            const p: *sdl.SDL_GPUComputePass = @ptrCast(@alignCast(pass));
            sdl.SDL_EndGPUComputePass(p);
        }

        /// For the blit/present pass — samples this texture as a regular fragment sampler.
        pub fn BindSampler(self: Self, render_pass: *anyopaque, slot: u32) void {
            const pass: *sdl.SDL_GPURenderPass = @ptrCast(@alignCast(render_pass));
            const binding = sdl.SDL_GPUTextureSamplerBinding{
                .texture = self.mTexture.?,
                .sampler = self.mSampler.?,
            };
            sdl.SDL_BindGPUFragmentSamplers(pass, slot, &binding, 1);
        }

        pub fn GetTexture(self: Self) *sdl.SDL_GPUTexture {
            return self.mTexture.?;
        }

        pub fn GetWidth(self: Self) usize {
            return self.mWidth;
        }
        pub fn GetHeight(self: Self) usize {
            return self.mHeight;
        }

        fn Create(self: *Self, engine_context: *EngineContext) !void {
            const device: *sdl.SDL_GPUDevice = @ptrCast(engine_context.mRenderer.mPlatform.GetDevice());

            const info = sdl.SDL_GPUTextureCreateInfo{
                .type = sdl.SDL_GPU_TEXTURETYPE_2D,
                .format = ToSDLTextureFormat(format),
                .usage = sdl.SDL_GPU_TEXTUREUSAGE_COMPUTE_STORAGE_READ |
                    sdl.SDL_GPU_TEXTUREUSAGE_COMPUTE_STORAGE_WRITE |
                    sdl.SDL_GPU_TEXTUREUSAGE_SAMPLER,
                .width = @intCast(self.mWidth),
                .height = @intCast(self.mHeight),
                .layer_count_or_depth = 1,
                .num_levels = 1,
                .sample_count = sdl.SDL_GPU_SAMPLECOUNT_1, // storage images: no MSAA
                .props = 0,
            };
            self.mTexture = sdl.SDL_CreateGPUTexture(device, &info) orelse return error.CreateComputeTexture;

            const sampler_info = sdl.SDL_GPUSamplerCreateInfo{
                .min_filter = sdl.SDL_GPU_FILTER_NEAREST,
                .mag_filter = sdl.SDL_GPU_FILTER_NEAREST,
                .mipmap_mode = sdl.SDL_GPU_SAMPLERMIPMAPMODE_NEAREST,
                .address_mode_u = sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
                .address_mode_v = sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
                .address_mode_w = sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
            };
            self.mSampler = sdl.SDL_CreateGPUSampler(device, &sampler_info) orelse return error.CreateComputeTexture;
        }

        fn Destroy(self: *Self, engine_context: *EngineContext) !void {
            const device: *sdl.SDL_GPUDevice = @ptrCast(engine_context.mRenderer.mPlatform.GetDevice());
            if (self.mTexture) |t| {
                sdl.SDL_ReleaseGPUTexture(device, t);
                self.mTexture = null;
            }
            if (self.mSampler) |s| {
                sdl.SDL_ReleaseGPUSampler(device, s);
                self.mSampler = null;
            }
        }

        fn ToSDLTextureFormat(f: TextureFormat) sdl.SDL_GPUTextureFormat {
            return switch (f) {
                .RGBA8 => sdl.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
                .BGRA8 => sdl.SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM,
                .RGBA16F => sdl.SDL_GPU_TEXTUREFORMAT_R16G16B16A16_FLOAT,
                .RGBA32F => sdl.SDL_GPU_TEXTUREFORMAT_R32G32B32A32_FLOAT,
                else => unreachable,
            };
        }
    };
}

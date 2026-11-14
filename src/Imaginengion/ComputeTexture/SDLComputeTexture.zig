const std = @import("std");
const TextureFormat = @import("../ECSComponents/AComponents.zig").Texture2D.TextureFormat;
const sdl = @import("../Core/CImports.zig").sdl;
const EngineContext = @import("../Core/EngineContext.zig");
const Tracy = @import("../Core/Tracy.zig");
const GPUAllocator = @import("../Core/GPUAllocator.zig");

pub fn SDLComputeStorageTexture(comptime format: TextureFormat) type {
    return struct {
        const Self = @This();

        pub const empty: Self = .{
            .mTexture = null,
            .mSampler = null,
            .mWidth = 0,
            .mHeight = 0,
            .mOwner = GPUAllocator.ENGINE,
        };

        mTexture: ?*sdl.SDL_GPUTexture,
        mSampler: ?*sdl.SDL_GPUSampler,
        mWidth: usize,
        mHeight: usize,
        /// who the GPU texture is made for (GPUAllocator.Owner), given by Init and Resize
        mOwner: GPUAllocator.Owner,

        pub fn Init(self: *Self, engine_context: *EngineContext, owner: GPUAllocator.Owner, width: usize, height: usize) !void {
            self.mWidth = width;
            self.mHeight = height;
            self.mOwner = owner;
            try self.Create(engine_context);
        }

        pub fn Deinit(self: *Self, engine_context: *EngineContext) void {
            self.Destroy(engine_context);
        }

        /// `owner` is who the texture is for (GPUAllocator.Owner): the world of the player it draws
        pub fn Resize(self: *Self, engine_context: *EngineContext, owner: GPUAllocator.Owner, width: usize, height: usize) !void {
            if (width < 1 or height < 1 or width > 8192 or height > 8192 or (width == self.mWidth and height == self.mHeight)) return;
            self.mWidth = width;
            self.mHeight = height;
            self.mOwner = owner;
            try self.Invalidate(engine_context);
        }

        pub fn Invalidate(self: *Self, engine_context: *EngineContext) !void {
            //recreates the GPU texture, so this is what a viewport resize costs
            const zone = Tracy.ZoneInit("SDLComputeTexture::Invalidate", @src());
            defer zone.Deinit();

            self.Destroy(engine_context);
            try self.Create(engine_context);
        }

        /// Begins a compute pass with this texture bound read-write at slot 0.
        /// cycle: true for a pass that writes every pixel fresh, false for a game pass under an overlay (it must see the
        /// overlay's writes).
        pub fn BeginComputePass(self: *Self, engine_context: *EngineContext, cycle: bool) *sdl.SDL_GPUComputePass {
            const cmd: *sdl.SDL_GPUCommandBuffer = @ptrCast(@alignCast(engine_context.mRenderer.mPlatform.GetFrameCmdBuff()));

            const storage_tex_binding = sdl.SDL_GPUStorageTextureReadWriteBinding{
                .texture = self.mTexture.?,
                .mip_level = 0,
                .layer = 0,
                .cycle = cycle,
            };

            const pass = sdl.SDL_BeginGPUComputePass(
                cmd,
                &storage_tex_binding,
                1, //NOTE: maigc number 1 here is that the binding for output texture is set to 1 on the shader
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

        /// Fills the whole texture with `color`, for a render with nothing to draw: a render pass that only clears,
        /// far cheaper than a compute pass over every pixel. A fresh texture is cycled in, since nothing earlier shows
        pub fn Clear(self: *Self, engine_context: *EngineContext, color: [4]f32) void {
            const cmd: *sdl.SDL_GPUCommandBuffer = @ptrCast(@alignCast(engine_context.mRenderer.mPlatform.GetFrameCmdBuff()));

            const target = sdl.SDL_GPUColorTargetInfo{
                .texture = self.mTexture.?,
                .clear_color = .{ .r = color[0], .g = color[1], .b = color[2], .a = color[3] },
                .load_op = sdl.SDL_GPU_LOADOP_CLEAR,
                .store_op = sdl.SDL_GPU_STOREOP_STORE,
                .cycle = true,
            };
            const pass = sdl.SDL_BeginGPURenderPass(cmd, &target, 1, null);
            std.debug.assert(pass != null);
            sdl.SDL_EndGPURenderPass(pass);
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

        /// False until the first Init or Resize with a usable size creates the GPU texture.
        pub fn IsCreated(self: Self) bool {
            return self.mTexture != null;
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
            const gpu = &engine_context.mGPUAllocator;
            const info = sdl.SDL_GPUTextureCreateInfo{
                .type = sdl.SDL_GPU_TEXTURETYPE_2D,
                .format = ToSDLTextureFormat(format),
                .usage = sdl.SDL_GPU_TEXTUREUSAGE_COMPUTE_STORAGE_READ |
                    sdl.SDL_GPU_TEXTUREUSAGE_COMPUTE_STORAGE_WRITE |
                    sdl.SDL_GPU_TEXTUREUSAGE_SAMPLER |
                    //only for Clear
                    sdl.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET,
                .width = @intCast(self.mWidth),
                .height = @intCast(self.mHeight),
                .layer_count_or_depth = 1,
                .num_levels = 1,
                .sample_count = sdl.SDL_GPU_SAMPLECOUNT_1, // storage images: no MSAA
                .props = 0,
            };
            self.mTexture = gpu.CreateTexture(engine_context, &info, self.mOwner) orelse return error.CreateComputeTexture;

            const sampler_info = sdl.SDL_GPUSamplerCreateInfo{
                .min_filter = sdl.SDL_GPU_FILTER_NEAREST,
                .mag_filter = sdl.SDL_GPU_FILTER_NEAREST,
                .mipmap_mode = sdl.SDL_GPU_SAMPLERMIPMAPMODE_NEAREST,
                .address_mode_u = sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
                .address_mode_v = sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
                .address_mode_w = sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
            };
            self.mSampler = gpu.CreateSampler(engine_context, &sampler_info, self.mOwner) orelse return error.CreateComputeTexture;
        }

        fn Destroy(self: *Self, engine_context: *EngineContext) void {
            const gpu = &engine_context.mGPUAllocator;
            if (self.mTexture) |t| {
                gpu.ReleaseTexture(engine_context, t);
                self.mTexture = null;
            }
            if (self.mSampler) |s| {
                gpu.ReleaseSampler(engine_context, s);
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

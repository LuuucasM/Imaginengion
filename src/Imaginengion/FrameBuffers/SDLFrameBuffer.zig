const std = @import("std");
const Vec4f32 = @import("../Math/LinAlg.zig").Vec4f32;
const TextureFormat = @import("../Assets/Assets.zig").Texture2D.TextureFormat;
const sdl = @import("../Core/CImports.zig").sdl;
const EngineContext = @import("../Core/EngineContext.zig");
const Texture2D = @import("../Assets/Assets.zig").Texture2D;
const AssetHandle = @import("../Assets/AssetHandle.zig");

pub fn FrameBuffer(comptime color_texture_formats: []const TextureFormat, comptime depth_texture_format: TextureFormat, comptime samples: usize) type {
    return struct {
        const Self = @This();

        pub const empty: Self = .{
            .mTextures = [_]Texture2D{.{}} ** color_texture_formats.len,
            .mDepthTexture = null,
            .mWidth = 0,
            .mHeight = 0,
        };

        const HasDepth = depth_texture_format != .None;
        const HasColor = color_texture_formats.len > 0;

        const SampleCount = switch (samples) {
            1 => sdl.SDL_GPU_SAMPLECOUNT_1,
            2 => sdl.SDL_GPU_SAMPLECOUNT_2,
            4 => sdl.SDL_GPU_SAMPLECOUNT_4,
            8 => sdl.SDL_GPU_SAMPLECOUNT_8,
            else => @compileError("Unsupported sample count - must be 1, 2, 4, or 8\n"),
        };

        mTextures: [color_texture_formats.len]?*sdl.SDL_GPUTexture,
        mSamplers: [color_texture_formats.len]?*sdl.SDL_GPUSampler,
        mDepthTexture: ?Texture2D,
        mWidth: usize,
        mHeight: usize,

        pub fn Init(self: Self, engine_context: *EngineContext, width: usize, height: usize) void {
            self.mWidth = width;
            self.mHeight = height;
            self.Create(engine_context);
        }
        pub fn Deinit(self: Self, engine_context: *EngineContext) void {
            self.Destroy(engine_context);
        }

        pub fn BeginRenderPass(self: *Self, engine_context: *EngineContext, clear_colors: [color_texture_formats.len]Vec4f32) *sdl.struct_SDL_GPURenderPass {
            const cmd: *sdl.SDL_GPUCommandBuffer = @ptrCast(@alignCast(engine_context.mRenderer.mPlatform.GetCommandBuff()));

            // Build color target infos — replaces glBindFramebuffer + glClearColor + glClear
            var color_targets: [color_texture_formats.len]sdl.SDL_GPUColorTargetInfo = undefined;
            inline for (0..color_texture_formats.len) |i| {
                color_targets[i] = sdl.SDL_GPUColorTargetInfo{
                    .texture = self.mTextures[i],
                    .mip_level = 0,
                    .layer_or_depth_plane = 0,
                    .clear_color = .{
                        .r = clear_colors[i][0],
                        .g = clear_colors[i][1],
                        .b = clear_colors[i][2],
                        .a = clear_colors[i][3],
                    },
                    .load_op = sdl.SDL_GPU_LOADOP_CLEAR, // replaces glClear
                    .store_op = sdl.SDL_GPU_STOREOP_STORE,
                    .resolve_texture = null,
                    .resolve_mip_level = 0,
                    .resolve_layer = 0,
                    .cycle = false,
                    .cycle_resolve_texture = false,
                    .padding1 = 0,
                    .padding2 = 0,
                };
            }

            // Build depth target info if present — replaces GL_DEPTH_BUFFER_BIT in glClear
            var depth_target: sdl.SDL_GPUDepthStencilTargetInfo = undefined;
            const depth_target_ptr: ?*sdl.SDL_GPUDepthStencilTargetInfo = if (HasDepth) blk: {
                const sdl_texture: *sdl.SDL_GPUTexture = @ptrCast(self.mDepthTexture.?.GetTexture());
                depth_target = sdl.SDL_GPUDepthStencilTargetInfo{
                    .texture = sdl_texture,
                    .clear_depth = 1.0,
                    .load_op = sdl.SDL_GPU_LOADOP_CLEAR,
                    .store_op = sdl.SDL_GPU_STOREOP_STORE,
                    .stencil_load_op = sdl.SDL_GPU_LOADOP_CLEAR,
                    .stencil_store_op = sdl.SDL_GPU_STOREOP_DONT_CARE,
                    .cycle = false,
                    .clear_stencil = 0,
                    .padding1 = 0,
                    .padding2 = 0,
                };
                break :blk &depth_target;
            } else null;

            const render_pass = sdl.SDL_BeginGPURenderPass(
                cmd,
                if (HasColor) &color_targets[0] else null,
                @intCast(color_texture_formats.len),
                depth_target_ptr,
            );
            std.debug.assert(render_pass != null);
            return render_pass.?;
        }

        pub fn EndRenderPass(_: *Self, render_pass: *anyopaque) void {
            const pass: *sdl.SDL_GPURenderPass = @ptrCast(@alignCast(render_pass));
            sdl.SDL_EndGPURenderPass(pass);
        }

        pub fn Resize(self: *Self, engine_context: *EngineContext, width: usize, height: usize) void {
            if (width < 1 or height < 1 or width > 8192 or height > 8192 or (width == self.mWidth and height == self.mHeight)) return;
            self.mWidth = width;
            self.mHeight = height;
            self.Invalidate(engine_context);
        }

        pub fn Invalidate(self: *Self, engine_context: *EngineContext) void {
            self.Destroy(engine_context);
            self.Create(engine_context);
        }

        pub fn GetColorTexture(self: Self, attachment_index: usize) ?*sdl.SDL_GPUTexture {
            std.debug.assert(attachment_index < color_texture_formats.len);
            return self.mTextures[attachment_index];
        }

        pub fn GetSampler(self: Self, attachment_index: usize) ?*sdl.SDL_GPUSampler {
            std.debug.assert(attachment_index < color_texture_formats.len);
            return self.mSamplers[attachment_index];
        }

        pub fn GetDepthTexture(self: Self) ?*sdl.SDL_GPUTexture {
            std.debug.assert(HasDepth);
            return self.mDepthTexture;
        }

        pub fn GetWidth(self: Self) usize {
            return self.mWidth;
        }
        pub fn GetHeight(self: Self) usize {
            return self.mHeight;
        }

        fn Create(self: *Self, engine_context: *EngineContext) void {
            const device: ?*sdl.SDL_GPUDevice = engine_context.mRenderer.mPlatform.GetDevice();
            inline for (color_texture_formats, 0..) |format, i| {
                const texture_info = sdl.SDL_GPUTextureCreateInfo{
                    .type = sdl.SDL_GPU_TEXTURETYPE_2D,
                    .format = ToSDLTextureFormat(format),
                    .usage = sdl.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET |
                        sdl.SDL_GPU_TEXTUREUSAGE_SAMPLER,
                    .width = @intCast(self.mWidth),
                    .height = @intCast(self.mHeight),
                    .layer_count_or_depth = 1,
                    .num_levels = 1,
                    .sample_count = SampleCount,
                    .props = 0,
                };
                self.mColorTextures[i] = sdl.SDL_CreateGPUTexture(device, &texture_info);
                if (self.mColorTextures[i] == null) {
                    std.log.err("SDLGPUFrameBuffer: SDL_CreateGPUTexture failed — {s}", .{sdl.SDL_GetError()});
                    return error.InitFailed;
                }

                const sampler_info = sdl.SDL_GPUSamplerCreateInfo{
                    .min_filter = sdl.SDL_GPU_FILTER_LINEAR,
                    .mag_filter = sdl.SDL_GPU_FILTER_LINEAR,
                    .mipmap_mode = sdl.SDL_GPU_SAMPLERMIPMAPMODE_LINEAR,
                    .address_mode_u = sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
                    .address_mode_v = sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
                    .address_mode_w = sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
                    .mip_lod_bias = 0,
                    .max_anisotropy = 1,
                    .compare_op = sdl.SDL_GPU_COMPAREOP_NEVER,
                    .min_lod = 0,
                    .max_lod = 0,
                    .enable_anisotropy = false,
                    .enable_compare = false,
                    .padding1 = 0,
                    .padding2 = 0,
                    .props = 0,
                };
                self.mSamplers[i] = sdl.SDL_CreateGPUSampler(device, &sampler_info);
                if (self.mSamplers[i] == null) {
                    std.log.err("SDLGPUFrameBuffer: SDL_CreateGPUSampler failed — {s}", .{sdl.SDL_GetError()});
                    return error.InitFailed;
                }
            }
            if (HasDepth) {
                const depth_info = sdl.SDL_GPUTextureCreateInfo{
                    .type = sdl.SDL_GPU_TEXTURETYPE_2D,
                    .format = ToSDLTextureFormat(depth_texture_format),
                    .usage = sdl.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
                    .width = @intCast(self.mWidth),
                    .height = @intCast(self.mHeight),
                    .layer_count_or_depth = 1,
                    .num_levels = 1,
                    .sample_count = SampleCount,
                    .props = 0,
                };
                self.mDepthTexture = sdl.SDL_CreateGPUTexture(device, &depth_info);
                if (self.mDepthTexture == null) {
                    std.log.err("SDLGPUFrameBuffer: depth SDL_CreateGPUTexture failed — {s}", .{sdl.SDL_GetError()});
                    return error.InitFailed;
                }
            }
        }

        fn Destroy(self: *Self, engine_context: *EngineContext) void {
            inline for (0..color_texture_formats.len) |i| {
                self.mTextures[i].?.Deinit(engine_context);
                self.mSamplers[i].?.Deinit(engine_context);
            }
            if (self.mDepthTexture) |t| t.Deinit(engine_context);
        }
        fn ToSDLTextureFormat(format: TextureFormat) sdl.SDL_GPUTextureFormat {
            return switch (format) {
                .RGBA8 => sdl.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
                .BGRA8 => sdl.SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM,
                .RGBA16Float => sdl.SDL_GPU_TEXTUREFORMAT_R16G16B16A16_FLOAT,
                .RGBA32Float => sdl.SDL_GPU_TEXTUREFORMAT_R32G32B32A32_FLOAT,
                .Depth32Float => sdl.SDL_GPU_TEXTUREFORMAT_D32_FLOAT,
            };
        }
    };
}

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

        mTextures: [color_texture_formats.len]Texture2D,
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

        pub fn BeginRenderPass(self: *Self, engine_context: *EngineContext, clear_colors: [color_texture_formats.len]Vec4f32) *anyopaque {
            const cmd: *sdl.SDL_GPUCommandBuffer = @ptrCast(@alignCast(engine_context.mRenderer.mPlatform.GetCommandBuff()));

            // Build color target infos — replaces glBindFramebuffer + glClearColor + glClear
            var color_targets: [color_texture_formats.len]sdl.SDL_GPUColorTargetInfo = undefined;
            inline for (0..color_texture_formats.len) |i| {
                const sdl_texture: *sdl.SDL_GPUTexture = @ptrCast(self.mTextures[i].GetTexture());
                color_targets[i] = sdl.SDL_GPUColorTargetInfo{
                    .texture = sdl_texture,
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
        pub fn GetColorTexture(self: Self, attachment_index: usize) *Texture2D {
            std.debug.assert(attachment_index < color_texture_formats.len);
            return &self.mTextures[attachment_index];
        }
        pub fn GetDepthTexture(self: Self) *Texture2D {
            std.debug.assert(HasDepth);
            return self.mDepthTexture;
        }

        pub fn BindColorAttachment(self: Self, render_pass: *anyopaque, attachment_index: usize, slot: u32) void {
            std.debug.assert(attachment_index < color_texture_formats.len);

            const pass: *sdl.SDL_GPURenderPass = @ptrCast(@alignCast(render_pass));

            const sdl_texture: *sdl.SDL_GPUTexture = self.mTextures[attachment_index].GetTexture();
            const sdl_sampler: *sdl.SDL_GPUSampler = self.mTextures[attachment_index].GetSampler();
            const binding = sdl.SDL_GPUTextureSamplerBinding{
                .texture = sdl_texture,
                .sampler = sdl_sampler,
            };
            sdl.SDL_BindGPUFragmentSamplers(pass, slot, &binding, 1);
        }
        pub fn BindDepthAttachment(self: Self, render_pass: *anyopaque, slot: u32) void {
            std.debug.assert(HasDepth);

            const pass: *sdl.SDL_GPURenderPass = @ptrCast(@alignCast(render_pass));

            const sdl_texture: *sdl.SDL_GPUTexture = self.mDepthTexture.?.GetTexture();

            const binding = sdl.SDL_GPUTextureSamplerBinding{
                .texture = sdl_texture,
                .sampler = null,
            };
            sdl.SDL_BindGPUFragmentSamplers(pass, slot, &binding, 1);
        }

        fn Create(self: *Self, engine_context: *EngineContext) void {
            inline for (color_texture_formats, 0..) |format, i| {
                self.mTextures[i].InitGen(engine_context, .{
                    .width = self.mWidth,
                    .height = self.mHeight,
                    .texture_format = format,
                    .is_render_target = true,
                });
            }
            if (HasDepth) {
                self.mDepthTexture.InitGen(engine_context, .{
                    .width = self.mWidth,
                    .height = self.mHeight,
                    .texture_format = depth_texture_format,
                    .is_render_target = true,
                });
            }
        }

        fn Destroy(self: *Self, engine_context: *EngineContext) void {
            inline for (0..color_texture_formats.len) |i| {
                self.mTextures[i].Deinit(engine_context);
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

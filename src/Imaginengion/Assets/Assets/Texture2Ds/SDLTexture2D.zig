const std = @import("std");
const sdl = @import("../../../Core/CImports.zig").sdl;
const stb = @import("../../../Core/CImports.zig").stb;
const EngineContext = @import("../../../Core/EngineContext.zig");
const SDLTexture2D = @This();

_Width: c_int = 0,
_Height: c_int = 0,
mTexture: ?*sdl.SDL_GPUTexture = null,
mSampler: ?*sdl.SDL_GPUSampler = null,

pub fn Init(self: *SDLTexture2D, engine_context: *EngineContext, _: []const u8, rel_path: []const u8, asset_file: std.fs.File) !void {
    const device: *sdl.SDL_GPUDevice = @ptrCast(@alignCast(engine_context.mRenderer.mRenderContext.GetDevice()));
    const frame_allocator = engine_context.FrameAllocator();

    var width: c_int = 0;
    var height: c_int = 0;
    var channels: c_int = 0;

    const fstats = try asset_file.stat();
    const contents = try asset_file.readToEndAlloc(frame_allocator, @intCast(fstats.size));

    stb.stbi_set_flip_vertically_on_load(1);

    const data = stb.stbi_load_from_memory(
        contents.ptr,
        @intCast(contents.len),
        &width,
        &height,
        &channels,
        4,
    );
    defer stb.stbi_image_free(data);

    if (data == null) {
        std.log.err("stbi_load_from_memory unable to correctly load the data for file {s}!\n", .{rel_path});
        return error.AssetInitFailed;
    }

    const pixel_data_size: u32 = @intCast(width * height * 4);

    const texture_info = sdl.SDL_GPUTextureCreateInfo{
        .type = sdl.SDL_GPU_TEXTURETYPE_2D,
        .format = sdl.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
        .usage = sdl.SDL_GPU_TEXTUREUSAGE_SAMPLER,
        .width = @intCast(width),
        .height = @intCast(height),
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .sample_count = sdl.SDL_GPU_SAMPLECOUNT_1,
        .props = 0,
    };

    self.mTexture = sdl.SDL_CreateGPUTexture(device, &texture_info);

    if (self.mTexture == null) {
        std.log.err("SDF_CreateGPUTexture failed for: {s} - {s}", .{ rel_path, sdl.SDL_GetError() });
        return error.AssetInitFailed;
    }

    const sampler_info = sdl.SDL_GPUSamplerCreateInfo{
        .min_filter = sdl.SDL_GPU_FILTER_LINEAR,
        .mag_filter = sdl.SDL_GPU_FILTER_LINEAR,
        .mipmap_mode = sdl.SDL_GPU_SAMPLERMIPMAPMODE_LINEAR,
        .address_mode_u = sdl.SDL_GPU_SAMPLERADDRESSMODE_REPEAT,
        .address_mode_v = sdl.SDL_GPU_SAMPLERADDRESSMODE_REPEAT,
        .address_mode_w = sdl.SDL_GPU_SAMPLERADDRESSMODE_REPEAT,
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
    self.mSampler = sdl.SDL_CreateGPUSampler(device, &sampler_info);

    if (self.mSampler == null) {
        std.log.err("SDL_CreateGPUSampler failed for: {s} - {s}", .{ rel_path, sdl.SDL_GetError() });
        return error.AssetInitFailed;
    }

    try UploadPixels(device, self.mTexture.?, data, pixel_data_size, @intCast(width), @intCast(height));

    self._Width = width;
    self._Height = height;
}

pub fn Deinit(self: *SDLTexture2D, engine_context: *EngineContext) !void {
    std.debug.assert(self.mTexture != null);
    std.debug.assert(self.mSampler != null);

    const device: *sdl.SDL_GPUDevice = @ptrCast(@alignCast(engine_context.mRenderer.mRenderContext.GetDevice()));

    sdl.SDL_ReleaseGPUTexture(device, self.mTexture.?);
    sdl.SDL_ReleaseGPUSampler(device, self.mSampler.?);

    self.mTexture = null;
    self.mSampler = null;
}
pub fn GetWidth(self: SDLTexture2D) usize {
    return @intCast(self._Width);
}
pub fn GetHeight(self: SDLTexture2D) usize {
    return @intCast(self._Height);
}

pub fn GetTexture(self: SDLTexture2D) *sdl.SDL_GPUTexture {
    std.debug.assert(self.mTexture != null);
    return self.mTexture;
}

pub fn GetSampler(self: SDLTexture2D) *sdl.SDL_GPUSampler {
    std.debug.assert(self.mSampler != null);
    return self.mSampler.?;
}

pub fn Bind(self: *SDLTexture2D, engine_context: *EngineContext, slot: u32) void {
    std.debug.assert(self.mTexture != null);
    std.debug.assert(self.mSampler != null);

    const render_pass: *sdl.SDL_GPURenderPass = @ptrCast(@alignCast(engine_context.mRenderer.mRenderContext.GetRenderPass()));

    const binding = sdl.SDL_GPUTextureSamplerBinding{
        .texture = self.mTexture,
        .sampler = self.mSampler,
    };
    sdl.SDL_BindGPUFragmentSamplers(render_pass, slot, &binding, 1);
}

pub fn UpdateDataPath(self: *SDLTexture2D, engine_context: *EngineContext, abs_path: []const u8) !void {
    var width: c_int = 0;
    var height: c_int = 0;
    var channels: c_int = 0;
    const frame_allocator = engine_context.FrameAllocator();

    const file = try std.fs.openFileAbsolute(abs_path, .{});
    defer file.close();
    const fstats = try file.stat();
    const contents = try file.readToEndAlloc(frame_allocator, @intCast(fstats.size));

    stb.stbi_set_flip_vertically_on_load(1);
    const data = stb.stbi_load_from_memory(
        contents.ptr,
        @intCast(contents.len),
        &width,
        &height,
        &channels,
        4,
    );
    defer stb.stbi_image_free(data);
    std.debug.assert(data != null);

    const pixel_data_size: u32 = @intCast(width * height * 4);

    const device: *sdl.SDL_GPUDevice = @ptrCast(@alignCast(engine_context.mRenderer.mRenderContext.GetDevice()));

    if (width != self._Width or height != self._Height) {
        sdl.SDL_ReleaseGPUTexture(device, self.mTexture);
        const texture_info = sdl.SDL_GPUTextureCreateInfo{
            .type = sdl.SDL_GPU_TEXTURETYPE_2D,
            .format = sdl.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
            .usage = sdl.SDL_GPU_TEXTUREUSAGE_SAMPLER,
            .width = @intCast(width),
            .height = @intCast(height),
            .layer_count_or_depth = 1,
            .num_levels = 1,
            .sample_count = sdl.SDL_GPU_SAMPLECOUNT_1,
            .props = 0,
        };
        self.mTexture = sdl.SDL_CreateGPUTexture(self.mDevice, &texture_info);
        self._Width = width;
        self._Height = height;
    }

    try UploadPixels(self.mDevice.?, self.mTexture.?, data, pixel_data_size, @intCast(width), @intCast(height));
}

fn UploadPixels(device: *sdl.SDL_GPUDevice, texture: *sdl.SDL_GPUTexture, data: ?*anyopaque, data_size: u32, width: u32, height: u32) !void {
    const transfer_info = sdl.SDL_GPUTransferBufferCreateInfo{
        .usage = sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = data_size,
        .props = 0,
    };
    const transfer_buf = sdl.SDL_CreateGPUTransferBuffer(device, &transfer_info);
    if (transfer_buf == null) return error.AssetInitFailed;
    defer sdl.SDL_ReleaseGPUTransferBuffer(device, transfer_buf);

    const mapped = sdl.SDL_MapGPUTransferBuffer(device, transfer_buf, false);
    if (mapped == null) return error.AssetInitFailed;
    @memcpy(@as([*]u8, @ptrCast(mapped))[0..data_size], @as([*]const u8, @ptrCast(data))[0..data_size]);
    sdl.SDL_UnmapGPUTransferBuffer(device, transfer_buf);

    const cmd = sdl.SDL_AcquireGPUCommandBuffer(device);
    if (cmd == null) return error.AssetInitFailed;

    const copy_pass = sdl.SDL_BeginGPUCopyPass(cmd);
    if (copy_pass == null) {
        _ = sdl.SDL_CancelGPUCommandBuffer(cmd);
        return error.AssetInitFailed;
    }

    const src = sdl.SDL_GPUTextureTransferInfo{
        .transfer_buffer = transfer_buf,
        .offset = 0,
        .pixels_per_row = width,
        .rows_per_layer = height,
    };

    const dst = sdl.SDL_GPUTextureRegion{
        .texture = texture,
        .mip_level = 0,
        .layer = 0,
        .x = 0,
        .y = 0,
        .z = 0,
        .w = width,
        .h = height,
        .d = 1,
    };
    sdl.SDL_UploadToGPUTexture(copy_pass, &src, &dst, false);

    sdl.SDL_EndGPUCopyPass(copy_pass);
    _ = sdl.SDL_SubmitGPUCommandBuffer(cmd);
}

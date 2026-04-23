const std = @import("std");
const sdl = @import("../../../Core/CImports.zig").sdl;
const stb = @import("../../../Core/CImports.zig").stb;
const EngineContext = @import("../../../Core/EngineContext.zig");
const SDLTexture2D = @This();

const SDL_TEXTURE_FORMAT = sdl.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM;

_Width: c_int = 0,
_Height: c_int = 0,
mTexture: ?*sdl.SDL_GPUTexture = null,
mSampler: ?*sdl.SDL_GPUSampler = null,
mBindlessInd: u32 = std.math.maxInt(u32),

pub fn Init(self: *SDLTexture2D, engine_context: *EngineContext, _: []const u8, rel_path: []const u8, asset_file: std.fs.File) !void {
    const device: *sdl.SDL_GPUDevice = @ptrCast(@alignCast(engine_context.mRenderer.mPlatform.GetDevice()));
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

    self.mTexture = CreateGPUTexture(device, @intCast(width), @intCast(height), false) orelse {
        std.log.err("SDL_CreateGPUTexture failed for: {s} — {s}", .{ rel_path, sdl.SDL_GetError() });
        return error.AssetInitFailed;
    };

    const pixel_data_size: u32 = @intCast(width * height * 4);
    try UploadPixels(device, self.mTexture.?, data, pixel_data_size, @intCast(width), @intCast(height));

    self._Width = width;
    self._Height = height;

    self.mBindlessInd = engine_context.mRenderer.mPlatform.RegisterTexture2D(self, SDL_TEXTURE_FORMAT);

    std.log.debug("SDLGPUTexture2D: loaded '{s}' → bindless slot {d}", .{ rel_path, self.mSlot });
}

pub fn InitGen(self: *SDLTexture2D, engine_context: *EngineContext, descriptor: GenDescriptor) !void {
    const device: *sdl.SDL_GPUDevice = @ptrCast(@alignCast(engine_context.mRenderer.mPlatform.GetDevice()));

    self.mTexture = CreateGPUTexture(device, descriptor.width, descriptor.height);
    self.mSampler = CreateSampler(device);

    self._Width = descriptor.width;
    self._Height = descriptor.height;

    self.mBindlessInd = try engine_context.mRenderer.mPlatform.RegisterTexture2D(self, SDL_TEXTURE_FORMAT);
}

pub fn Deinit(self: *SDLTexture2D, engine_context: *EngineContext) !void {
    std.debug.assert(self.mTexture != null);
    std.debug.assert(self.mBindlessInd != std.math.maxInt(u32));

    engine_context.mRenderer.mPlatform.Unregister(self.mBindlessInd);

    const device: *sdl.SDL_GPUDevice = @ptrCast(@alignCast(engine_context.mRenderer.mPlatform.GetDevice()));
    sdl.SDL_ReleaseGPUTexture(device, self.mTexture);
    sdl.SDL_ReleaseGPUSampler(device, self.mSampler);

    self.mTexture = null;
    self.mSampler = null;
}
pub fn GetWidth(self: SDLTexture2D) usize {
    return @intCast(self._Width);
}
pub fn GetHeight(self: SDLTexture2D) usize {
    return @intCast(self._Height);
}
pub fn GetSlot(self: SDLTexture2D) usize {
    return self.mBindlessInd;
}

pub fn GetTexture(self: SDLTexture2D) *sdl.SDL_GPUTexture {
    std.debug.assert(self.mTexture != null);
    return self.mTexture;
}

pub fn GetSampler(self: SDLTexture2D) *sdl.SDL_GPUSampler {
    std.debug.assert(self.mSampler);
    return self.mSampler;
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

    const device: *sdl.SDL_GPUDevice = @ptrCast(@alignCast(engine_context.mRenderer.mPlatform.GetDevice()));

    if (width != self._Width or height != self._Height) {
        engine_context.mRenderer.mPlatform.Unregister(self.mBindlessInd);
        sdl.SDL_ReleaseGPUTexture(device, self.mTexture);

        self.mTexture = CreateGPUTexture(device, width, height);

        self._Width = width;
        self._Height = height;

        self.mBindlessInd = engine_context.mRenderer.mPlatform.RegisterTexture2D(self, SDL_TEXTURE_FORMAT);
    }

    const cmd = sdl.SDL_AcquireGPUCommandBuffer(self.mDevice) orelse return error.AssetInitFailed;
    try UploadPixels(self.mDevice.?, self.mTexture.?, data, pixel_data_size, @intCast(width), @intCast(height));
    _ = sdl.SDL_SubmitGPUCommandBuffer(cmd);
}

pub fn UpdateDataGen(self: *SDLTexture2D, engine_context: *EngineContext, descriptor: GenDescriptor) !void {
    const device: *sdl.SDL_GPUDevice = @ptrCast(@alignCast(engine_context.mRenderer.mPlatform.GetDevice()));
    if (descriptor.width != self._Width or descriptor.height != self._Height) {
        engine_context.mRenderer.mPlatform.Unregister(self.mBindlessInd);
        sdl.SDL_ReleaseGPUTexture(device, self.mTexture);

        self.mTexture = CreateGPUTexture(device, descriptor.width, descriptor.height);

        self._Width = descriptor.width;
        self._Height = descriptor.height;

        self.mBindlessInd = engine_context.mRenderer.mPlatform.RegisterTexture2D(self, SDL_TEXTURE_FORMAT);
    }
}

fn CreateGPUTexture(device: *sdl.SDL_GPUDevice, width: u32, height: u32, is_render_target: bool) ?*sdl.SDL_GPUTexture {
    const usage = sdl.SDL_GPU_TEXTUREUSAGE_SAMPLER | if (is_render_target) sdl.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET else 0;
    const info = sdl.SDL_GPUTextureCreateInfo{
        .type = sdl.SDL_GPU_TEXTURETYPE_2D,
        .format = sdl.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
        .usage = usage,
        .width = width,
        .height = height,
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .sample_count = sdl.SDL_GPU_SAMPLECOUNT_1,
        .props = 0,
    };
    return sdl.SDL_CreateGPUTexture(device, &info);
}

fn CreateSampler(device: *sdl.SDL_GPUDevice) ?*sdl.SDL_GPUSampler {
    const info = sdl.SDL_GPUSamplerCreateInfo{
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
    return sdl.SDL_CreateGPUSampler(device, &info);
}

fn UploadPixels(device: *sdl.SDL_GPUDevice, texture: *sdl.SDL_GPUTexture, data: ?*anyopaque, data_size: u32, width: u32, height: u32) !void {
    const transfer_info = sdl.SDL_GPUTransferBufferCreateInfo{
        .usage = sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = data_size,
        .props = 0,
    };
    const transfer_buf = sdl.SDL_CreateGPUTransferBuffer(device, &transfer_info) orelse return error.AssetInitFailed;
    defer sdl.SDL_ReleaseGPUTransferBuffer(device, transfer_buf);

    const mapped = sdl.SDL_MapGPUTransferBuffer(device, transfer_buf, false) orelse return error.AssetInitFailed;

    @memcpy(@as([*]u8, @ptrCast(mapped))[0..data_size], @as([*]const u8, @ptrCast(data))[0..data_size]);

    sdl.SDL_UnmapGPUTransferBuffer(device, transfer_buf);

    const cmd = sdl.SDL_AcquireGPUCommandBuffer(device) orelse return error.AssetInitFailed;

    const copy_pass = sdl.SDL_BeginGPUCopyPass(cmd) orelse {
        _ = sdl.SDL_CancelGPUCommandBuffer(cmd);
        return error.AssetInitFailed;
    };

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

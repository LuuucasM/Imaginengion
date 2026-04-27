const std = @import("std");
const sdl = @import("../../../Core/CImports.zig").sdl;
const stb = @import("../../../Core/CImports.zig").stb;
const EngineContext = @import("../../../Core/EngineContext.zig");
const GenDescriptor = @import("../Texture2D.zig").GenDescriptor;
const TextureManager = @import("../../../TextureManager/TextureManager.zig");
const SDLTexture2D = @This();

const SDL_TEXTURE_FORMAT = sdl.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM;

_Width: c_int = 0,
_Height: c_int = 0,
_TextureHandle: u32 = 0,
_TextureManager: *TextureManager = undefined,

pub fn Init(self: *SDLTexture2D, engine_context: *EngineContext, _: []const u8, rel_path: []const u8, asset_file: std.Io.File) !void {
    const frame_allocator = engine_context.FrameAllocator();

    var width: c_int = 0;
    var height: c_int = 0;
    var channels: c_int = 0;

    var file_reader = asset_file.reader(engine_context.Io(), &.{});
    const contents = try file_reader.interface.allocRemaining(frame_allocator, .unlimited);

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

    self._TextureHandle = try engine_context.mRenderer.mTextureManager.Register(engine_context, data, @intCast(width), @intCast(height));

    self._Width = width;
    self._Height = height;
    self._TextureManager = &engine_context.mRenderer.mTextureManager;

    std.log.debug("SDLGPUTexture2D: loaded '{s}' → bindless slot {d}", .{ rel_path, self._TextureHandle });
}

pub fn InitGen(self: *SDLTexture2D, engine_context: *EngineContext, descriptor: GenDescriptor) !void {
    engine_context.mRenderer.mTextureManager.Register(engine_context, descriptor.data, descriptor.width, descriptor.height);

    self._Width = descriptor.width;
    self._Height = descriptor.height;

    std.log.debug("SDLGPUTexture2D.InitGen: {d}x{d}", .{ descriptor.width, descriptor.height });
}

pub fn Deinit(self: *SDLTexture2D, engine_context: *EngineContext) !void {
    engine_context.mRenderer.mTextureManager.Unregister(self._TextureHandle);
    self._TextureHandle = 0;
}
pub fn GetWidth(self: SDLTexture2D) usize {
    return @intCast(self._Width);
}
pub fn GetHeight(self: SDLTexture2D) usize {
    return @intCast(self._Height);
}

pub fn GetTextureHandle(self: SDLTexture2D) u32 {
    return self._TextureHandle;
}

pub fn GetTexture(self: SDLTexture2D) *sdl.SDL_GPUTexture {
    return self._TextureManager.GetTexture();
}

pub fn GetSampler(self: SDLTexture2D) *sdl.SDL_GPUSampler {
    return self._TextureManager.GetSampler();
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

    engine_context.mRenderer.mTextureManager.Unregister(self._TextureHandle);
    engine_context.mRenderer.mTextureManager.Register(engine_context, data, width, height);

    self._Width = width;
    self._Height = height;
}

pub fn UpdateDataGen(self: *SDLTexture2D, engine_context: *EngineContext, descriptor: GenDescriptor) !void {
    engine_context.mRenderer.mTextureManager.Register(engine_context, descriptor.data, descriptor.width, descriptor.height);

    self._Width = descriptor.width;
    self._Height = descriptor.height;
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

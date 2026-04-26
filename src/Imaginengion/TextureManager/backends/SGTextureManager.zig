const std = @import("std");
const sdl = @import("../../Core/CImports.zig").sdl;
const Bin = @import("../Bin.zig").Bin;
const EngineContext = @import("../../Core/EngineContext.zig");
const SkipField = @import("../../Core/SkipField.zig").StaticSkipField;

const SGTextureManager = @This();

pub const ATLAS_SIZE: u32 = 4096;
pub const MAX_POSSIBLE_LAYERS = 512;
pub const PADDING: u32 = 2;
pub const NUM_BINS: u32 = 7;
pub const BYTES_PER_LAYER: usize = ATLAS_SIZE * ATLAS_SIZE * 4; // RGBA8
pub const SLOT_BYTES = 18;
pub const LAYER_BYTES = 10;
pub const BINS_BYTES = 4;

const BIN64 = Bin(ATLAS_SIZE, 64, 2);
const BIN128 = Bin(ATLAS_SIZE, 128, 2);
const BIN256 = Bin(ATLAS_SIZE, 256, 2);
const BIN512 = Bin(ATLAS_SIZE, 512, 2);
const BIN1024 = Bin(ATLAS_SIZE, 1024, 2);
const BIN2048 = Bin(ATLAS_SIZE, 2048, 2);
const BIN4096 = Bin(ATLAS_SIZE, 4096, 2);

const LayersFreeListT = SkipField(MAX_POSSIBLE_LAYERS);
const SlotFreeListT = SkipField(BIN64.TotalSlots);
const SizeBoundsList = [_]usize{
    BIN64.MaxTextureSize,
    BIN128.MaxTextureSize,
    BIN256.MaxTextureSize,
    BIN512.MaxTextureSize,
    BIN1024.MaxTextureSize,
    BIN2048.MaxTextureSize,
    BIN4096.MaxTextureSize,
};

mTexture: ?*sdl.SDL_GPUTexture = null,
mSampler: ?*sdl.SDL_GPUSampler = null,
mMaxLayers: usize = 0,
mBins: std.ArrayList(LayersFreeListT) = .empty,
mLayers: std.ArrayList(SlotFreeListT) = .empty,
mLayersFreeList: LayersFreeListT = .NoSkip,
mNumLayers: usize = 0,

pub fn Init(self: *SGTextureManager, engine_context: *EngineContext, vram_bytes_size: usize) !void {
    self.mMaxLayers = vram_bytes_size / BYTES_PER_LAYER;

    std.debug.assert(self.mMaxLayers != 0);

    std.log.info("TextureAtlasManager: {d} layers ({d}MB VRAM budget)", .{
        self.mMaxLayers,
        vram_bytes_size / (1024 * 1024),
    });

    const texture_info = sdl.SDL_GPUTextureCreateInfo{
        .type = sdl.SDL_GPU_TEXTURETYPE_2D_ARRAY,
        .format = sdl.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
        .usage = sdl.SDL_GPU_TEXTUREUSAGE_SAMPLER | sdl.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET,
        .width = ATLAS_SIZE,
        .height = ATLAS_SIZE,
        .layer_count_or_depth = @intCast(self.mMaxLayers),
        .num_levels = 1,
        .sample_count = sdl.SDL_GPU_SAMPLECOUNT_1,
        .props = 0,
    };

    const device: ?*sdl.SDL_GPUDevice = @ptrCast(engine_context.mRenderer.mPlatform.GetDevice());

    self.mTexture = sdl.SDL_CreateGPUTexture(device, &texture_info) orelse {
        std.log.err("TextureAtlasManager: SDL_CreateGPUTexture failed — {s}", .{sdl.SDL_GetError()});
        return error.InitFailed;
    };

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
    self.mSampler = sdl.SDL_CreateGPUSampler(device, &sampler_info) orelse {
        std.log.err("TextureAtlasManager: SDL_CreateGPUSampler failed — {s}", .{sdl.SDL_GetError()});
        return error.InitFailed;
    };

    for (0..self.mMaxLayers) |i| {
        _ = i;
        try self.mLayers.append(engine_context.EngineAllocator(), .NoSkip);
    }

    for (0..NUM_BINS) |i| {
        _ = i;
        try self.mBins.append(engine_context.EngineAllocator(), .AllSkip);
    }
}

pub fn Deinit(self: *SGTextureManager, engine_context: *EngineContext) void {
    const device: ?*sdl.SDL_GPUDevice = engine_context.mRenderer.mPlatform.GetDevice();
    sdl.SDL_WaitForGPUIdle(device);
    self.mBins.deinit(engine_context.EngineAllocator());
    self.mLayers.deinit(engine_context.EngineAllocator());

    if (self.mSampler) |s| sdl.SDL_ReleaseGPUSampler(self.mDevice, s);
    if (self.mTexture) |t| sdl.SDL_ReleaseGPUTexture(self.mDevice, t);

    self.mTexture = null;
    self.mSampler = null;
}

pub fn Register(self: *SGTextureManager, engine_context: *EngineContext, data: ?*anyopaque, width: usize, height: usize) !u32 {
    const max_dim = @max(width, height);

    const bin_index = std.sort.lowerBound(
        usize,
        SizeBoundsList,
        max_dim,
        struct {
            fn comparison(_: void, key: usize, mid: usize) std.math.Order {
                return std.math.order(key, mid);
            }
        }.comparison,
    );

    if (bin_index == SizeBoundsList.len) {
        std.log.err("TextureAtlasManager: texture {d}x{d} exceeds max size {d}", .{
            width, height, BIN2048.MaxTextureSize,
        });
        return error.TextureTooLarge;
    }

    const layer_index, const slot_index = try self.FindLayerIndex(bin_index);

    errdefer {
        self.mLayers.items[layer_index].ChangeToUnskipped(slot_index);
        self.CheckReleaseLayer(bin_index, layer_index);
    }

    const device: ?*sdl.SDL_GPUDevice = @ptrCast(engine_context.mRenderer.mPlatform.GetDevice());

    const offset_x, const offset_y = CalculateOffsets(bin_index, slot_index);

    if (data) |d| {
        try self.UpdateToLayer(device, d, width, height, layer_index, offset_x, offset_y);
    }

    return (@as(u32, slot_index) << (LAYER_BYTES + BINS_BYTES)) | (@as(u32, layer_index) << BINS_BYTES) | @as(u32, bin_index);
}

pub fn Bind(self: SGTextureManager, render_pass: *anyopaque) void {
    const sdl_render_pass: *sdl.SDL_GPURenderPass = @ptrCast(render_pass);

    const binding = sdl.SDL_GPUTextureSamplerBinding{
        .texture = self.mTexture,
        .sampler = self.mSampler,
    };
    sdl.SDL_BindGPUFragmentSamplers(sdl_render_pass, 0, &binding, 1);
}

pub fn Unregister(self: *SGTextureManager, texture_location: u32) void {
    const layer_index = GetLayerIndex(texture_location);
    const slot_index = GetSlotIndex(texture_location);
    const bin_index = GetBinIndex(texture_location);

    std.debug.assert(layer_index < self.mLayers.items.len);
    self.mLayers.items[layer_index].ChangeToUnskipped(@intCast(slot_index));

    self.CheckReleaseLayer(bin_index, layer_index);
}

pub fn GetNormalizedOffsets(_: SGTextureManager, texture_handle: u32) struct { f32, f32 } {
    const bin_index = GetBinIndex(texture_handle);
    const slot_index = GetSlotIndex(texture_handle);

    const x_pixel_offset, const y_pixel_offset = CalculateOffsets(bin_index, slot_index);

    return .{
        @as(f32, @floatFromInt(x_pixel_offset)) / @as(f32, @floatFromInt(ATLAS_SIZE)),
        @as(f32, @floatFromInt(y_pixel_offset)) / @as(f32, @floatFromInt(ATLAS_SIZE)),
    };
}

pub fn GetPixelOffsets(_: SGTextureManager, texture_handle: u32) struct { usize, usize } {
    const bin_index = GetBinIndex(texture_handle);
    const slot_index = GetSlotIndex(texture_handle);

    return CalculateOffsets(bin_index, slot_index);
}

pub fn GetTexture(self: SGTextureManager) *sdl.SDL_GPUTexture {
    return self.mTexture.?;
}
pub fn GetSampler(self: SGTextureManager) *sdl.SDL_GPUSampler {
    return self.mSampler.?;
}

fn FindLayerIndex(self: *SGTextureManager, bin_index: usize) !struct { usize, usize } {
    var iter = self.mBins.items[bin_index].Iterator();
    const bin_total_slots = BinIndToTotalSlots(bin_index);

    while (iter.next()) |layer_index| {
        //if we go into the while loop then this layer_index is one that the bin owns
        if (self.mLayers.items[layer_index].GetFirstUnskipped()) |slot_index| {
            if (slot_index < bin_total_slots) {
                //if we can get an unskipped index that means theres space in this layer so return the slot index
                self.mLayers.items[layer_index].ChangeToSkipped(slot_index);
                return .{ layer_index, slot_index };
            }
        }
    }

    //we did not get a layer index while iterating through the bins freelist so we need to try and claim a new one
    if (self.mLayersFreeList.GetFirstUnskipped()) |layer_index| {
        self.mBins.items[bin_index].ChangeToUnskipped(layer_index);
        self.mLayersFreeList.ChangeToSkipped(layer_index);

        const slot_index = self.mLayers.items[layer_index].GetFirstUnskipped().?;
        self.mLayers.items[layer_index].ChangeToSkipped(slot_index);

        return .{ layer_index, slot_index };
    } else {
        //no more available layers so error
        return error.OutOfTextureMemory;
    }
}

fn CheckReleaseLayer(self: *SGTextureManager, bin_index: usize, layer_index: usize) void {
    if (self.mLayers.items[layer_index].IsAllUnskipped()) {
        self.mBins.items[bin_index].ChangeToSkipped(@intCast(layer_index));
        self.mLayersFreeList.ChangeToUnskipped(@intCast(layer_index));
        self.mLayers.items[layer_index] = .NoSkip;
    }
}

fn CalculateOffsets(bin_index: usize, slot_index: usize) struct { usize, usize } {
    const slot_col = slot_index % BinIndToSlotsPerRow(bin_index);
    const slot_row = slot_index / BinIndToSlotsPerRow(bin_index);
    return .{ slot_col * BinIndToSlotSize(bin_index) + PADDING, slot_row * BinIndToSlotSize(bin_index) + PADDING };
}

fn UpdateToLayer(self: *SGTextureManager, device: ?*sdl.SDL_GPUDevice, pixels: *anyopaque, width: usize, height: usize, layer_index: usize, offset_x: usize, offset_y: usize) !void {
    const data_size = width * height * 4; //4 because RGBA8

    const transfer_info = sdl.SDL_GPUTransferBufferCreateInfo{
        .usage = sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = data_size,
        .props = 0,
    };

    const transfer_buf = sdl.SDL_CreateGPUTransferBuffer(device, &transfer_info) orelse return error.UpdateFailed;
    defer sdl.SDL_ReleaseGPUTransferBuffer(device, transfer_buf);

    const mapped = sdl.SDL_MapGPUTransferBuffer(device, transfer_buf, false) orelse return error.InitFailed;
    @memcpy(
        @as([*]u8, @ptrCast(mapped))[0..data_size],
        @as([*]const u8, @ptrCast(pixels))[0..data_size],
    );
    sdl.SDL_UnmapGPUTransferBuffer(device, transfer_buf);

    const cmd = sdl.SDL_AcquireGPUCommandBuffer(device) orelse return error.InitFailed;
    const copy_pass = sdl.SDL_BeginGPUCopyPass(cmd) orelse {
        _ = sdl.SDL_CancelGPUCommandBuffer(cmd);
        return error.InitFailed;
    };

    const src = sdl.SDL_GPUTextureTransferInfo{
        .transfer_buffer = transfer_buf,
        .offset = 0,
        .pixels_per_row = width,
        .rows_per_layer = height,
    };

    const dst = sdl.SDL_GPUTextureRegion{
        .texture = self.mTexture,
        .mip_level = 0,
        .layer = layer_index, // which layer in the array
        .x = offset_x, // horizontal offset within the layer
        .y = offset_y, // vertical offset within the layer
        .z = 0,
        .w = width,
        .h = height,
        .d = 1,
    };

    sdl.SDL_UploadToGPUTexture(copy_pass, &src, &dst, false);
    sdl.SDL_EndGPUCopyPass(copy_pass);
    _ = sdl.SDL_SubmitGPUCommandBuffer(cmd);
}

fn BinIndToSlotsPerRow(bin_index: usize) usize {
    return switch (bin_index) {
        0 => BIN64.SlotsPerRow,
        1 => BIN128.SlotsPerRow,
        2 => BIN256.SlotsPerRow,
        3 => BIN512.SlotsPerRow,
        4 => BIN1024.SlotsPerRow,
        5 => BIN2048.SlotsPerRow,
        6 => BIN4096.SlotsPerRow,
        else => undefined,
    };
}

fn BinIndToSlotSize(bin_index: usize) usize {
    return switch (bin_index) {
        0 => BIN64.SlotSize,
        1 => BIN128.SlotSize,
        2 => BIN256.SlotSize,
        3 => BIN512.SlotSize,
        4 => BIN1024.SlotSize,
        5 => BIN2048.SlotSize,
        6 => BIN4096.SlotSize,
        else => undefined,
    };
}

fn BinIndToTotalSlots(bin_index: usize) usize {
    return switch (bin_index) {
        0 => BIN64.TotalSlots,
        1 => BIN128.TotalSlots,
        2 => BIN256.TotalSlots,
        3 => BIN512.TotalSlots,
        4 => BIN1024.TotalSlots,
        5 => BIN2048.TotalSlots,
        6 => BIN4096.TotalSlots,
        else => undefined,
    };
}

pub fn GetSlotIndex(loc: u32) usize {
    return @intCast((loc >> (LAYER_BYTES + BINS_BYTES)) & ((1 << SLOT_BYTES) - 1));
}

pub fn GetLayerIndex(loc: u32) usize {
    return @intCast((loc >> BINS_BYTES) & ((1 << LAYER_BYTES) - 1));
}

pub fn GetBinIndex(loc: u32) usize {
    return @intCast(loc & ((1 << BINS_BYTES) - 1));
}

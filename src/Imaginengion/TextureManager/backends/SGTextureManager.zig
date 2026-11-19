//! The texture atlas on SDL's GPU API: one RGBA8 texture array that every texture and shown render target is copied
//! into, shared by every world, so a shader finds any texture from one u32 handle (AtlasHandle) instead of binding it:
//! bindless, without the bindless resources SDL's GPU API doesn't have. Where each texture goes is AtlasSlots'.
//!
//! The array grows a layer at a time as it fills, up to the most it may have (mMaxLayers, from the budget it was given),
//! and gives back the free layers at its end once there are a few (OnFrameEnd). Either way it is made again at its new
//! size with every layer kept copied across on the GPU, to the same layer, so no handle changes. An array replaced while
//! a frame is being recorded may already be in that frame's commands, so it is only let go of once the frame is
//! submitted.
const std = @import("std");
const sdl = @import("../../Core/CImports.zig").sdl;
const GPUAllocator = @import("../../Core/GPUAllocator.zig");
const EngineContext = @import("../../Core/EngineContext.zig");
const Tracy = @import("../../Core/Tracy.zig");
const AtlasHandle = @import("../AtlasHandle.zig");
const AtlasSlots = @import("../AtlasSlots.zig");

const MathTypes = @import("../../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;
const Vec3 = MathTypes.Vec3;

const SGTextureManager = @This();

pub const ATLAS_SIZE = AtlasHandle.ATLAS_SIZE;
pub const BYTES_PER_LAYER: usize = ATLAS_SIZE * ATLAS_SIZE * 4; // RGBA8
/// Free layers left at the end when it shrinks, so loading the next texture doesn't grow it straight back
const SPARE_LAYERS = 1;

mTexture: ?*sdl.SDL_GPUTexture = null,
mSampler: ?*sdl.SDL_GPUSampler = null,
/// The most layers it may grow to
mMaxLayers: usize = 0,
mSlots: AtlasSlots = .{},
/// Arrays replaced while a frame was being recorded, let go of once it is submitted (OnFrameEnd)
mRetired: std.ArrayList(*sdl.SDL_GPUTexture) = .empty,

/// Starts with one layer, and may grow to as many as `vram_bytes_size` holds
pub fn Init(self: *SGTextureManager, engine_context: *EngineContext, vram_bytes_size: usize) !void {
    const zone = Tracy.ZoneInit("SGTextureManager::Init", @src());
    defer zone.Deinit();

    self.mMaxLayers = @min(vram_bytes_size / BYTES_PER_LAYER, AtlasHandle.MAX_LAYERS);
    std.debug.assert(self.mMaxLayers != 0);
    std.log.info("TextureAtlasManager: up to {d} layers ({d}MB VRAM budget)", .{ self.mMaxLayers, vram_bytes_size / (1024 * 1024) });

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
    self.mSampler = engine_context.mGPUAllocator.CreateSampler(engine_context, &sampler_info, GPUAllocator.ENGINE, "Texture atlas") orelse {
        std.log.err("TextureAtlasManager: SDL_CreateGPUSampler failed — {s}", .{sdl.SDL_GetError()});
        return error.InitFailed;
    };

    try self.Resize(engine_context, 1, .Now);
}

pub fn Deinit(self: *SGTextureManager, engine_context: *EngineContext) void {
    const device: ?*sdl.SDL_GPUDevice = @ptrCast(engine_context.mRenderer.mPlatform.GetDevice());
    _ = sdl.SDL_WaitForGPUIdle(device);
    self.ReleaseRetired(engine_context);
    self.mRetired.deinit(engine_context.Keep());
    self.mSlots.Deinit(engine_context.Keep());

    if (self.mSampler) |s| engine_context.mGPUAllocator.ReleaseSampler(engine_context, s);
    if (self.mTexture) |t| engine_context.mGPUAllocator.ReleaseTexture(engine_context, t);

    self.mTexture = null;
    self.mSampler = null;
}

/// A slot for a texture `width` by `height`, its pixels copied in if given (a render target's are copied in each frame
/// that shows it, CopyFromTexture). Grows the array a layer when it is full. The slot is counted on the GPU allocator
/// for `owner`
pub fn Register(self: *SGTextureManager, engine_context: *EngineContext, data: ?*anyopaque, width: usize, height: usize, owner: GPUAllocator.Owner) !u32 {
    const zone = Tracy.ZoneInit("SGTextureManager::Register", @src());
    defer zone.Deinit();

    const class = AtlasHandle.ClassOf(width, height) orelse {
        std.log.err("TextureAtlasManager: texture {d}x{d} exceeds max size {d}", .{ width, height, AtlasHandle.MaxTextureSize(AtlasHandle.CLASS_COUNT - 1) });
        return error.TextureTooLarge;
    };

    const handle = while (true) {
        if (try self.mSlots.Alloc(engine_context.Keep(), class)) |handle| break handle;
        if (self.mSlots.LayerCount() >= self.mMaxLayers) return error.OutOfTextureMemory;
        //this may be in the middle of recording a frame that already uses the array
        try self.Resize(engine_context, self.mSlots.LayerCount() + 1, .AfterFrame);
    };
    errdefer self.mSlots.Free(handle);
    const slot_size: u64 = AtlasHandle.SlotSize(class);
    try engine_context.mGPUAllocator.AtlasTook(engine_context, handle, slot_size * slot_size * 4, owner);
    errdefer engine_context.mGPUAllocator.AtlasGave(handle);

    if (data) |d| {
        const device: ?*sdl.SDL_GPUDevice = @ptrCast(engine_context.mRenderer.mPlatform.GetDevice());
        try self.UpdateToLayer(engine_context, device, d, width, height, AtlasHandle.Layer(handle), AtlasHandle.PixelX(handle), AtlasHandle.PixelY(handle));
    }
    return handle;
}

pub fn Unregister(self: *SGTextureManager, engine_context: *EngineContext, texture_location: u32) void {
    std.debug.assert(AtlasHandle.Layer(texture_location) < self.mSlots.LayerCount());
    engine_context.mGPUAllocator.AtlasGave(texture_location);
    self.mSlots.Free(texture_location);
}

/// Once a frame, after it has been submitted: lets go of the arrays replaced while it was recorded, and gives back the
/// free layers at the end when there are more than SPARE_LAYERS of them
pub fn OnFrameEnd(self: *SGTextureManager, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("SGTextureManager::OnFrameEnd", @src());
    defer zone.Deinit();
    self.ReleaseRetired(engine_context);

    const free = self.mSlots.TrailingFreeLayers();
    const layers = self.mSlots.LayerCount();
    if (free <= SPARE_LAYERS or layers <= 1) return;
    const keep = @max(1, layers - free + SPARE_LAYERS);
    //nothing is being recorded now, and SDL keeps a released array until the submitted frames using it are done
    try self.Resize(engine_context, keep, .Now);
}

/// Copies `width` x `height` of `source` (a GPU texture of the same RGBA8 format, from its top left corner) into the slot
/// `texture_location` was registered with, on the GPU, in `copy_pass` (RenderPlatform.BeginCopyPass) of the frame's
/// command buffer: after whatever drew into `source` earlier in it, and before anything that samples the slot later in it
pub fn CopyFromTexture(self: *SGTextureManager, copy_pass: *anyopaque, source: *anyopaque, texture_location: u32, width: usize, height: usize) void {
    const zone = Tracy.ZoneInit("SGTextureManager::CopyFromTexture", @src());
    defer zone.Deinit();

    const src = sdl.SDL_GPUTextureLocation{ .texture = @ptrCast(@alignCast(source)), .mip_level = 0, .layer = 0, .x = 0, .y = 0, .z = 0 };
    const dst = sdl.SDL_GPUTextureLocation{
        .texture = self.mTexture,
        .mip_level = 0,
        .layer = AtlasHandle.Layer(texture_location),
        .x = AtlasHandle.PixelX(texture_location),
        .y = AtlasHandle.PixelY(texture_location),
        .z = 0,
    };
    sdl.SDL_CopyGPUTextureToTexture(@ptrCast(@alignCast(copy_pass)), &src, &dst, @intCast(width), @intCast(height), 1, false);
}

pub fn Bind(self: SGTextureManager, render_pass: *anyopaque) void {
    const sdl_render_pass: *sdl.SDL_GPURenderPass = @ptrCast(render_pass);

    const binding = sdl.SDL_GPUTextureSamplerBinding{
        .texture = self.mTexture,
        .sampler = self.mSampler,
    };
    sdl.SDL_BindGPUFragmentSamplers(sdl_render_pass, 0, &binding, 0);
}

pub fn BindCompute(self: SGTextureManager, compute_pass: *anyopaque) void {
    const sdl_compute_pass: *sdl.SDL_GPUComputePass = @ptrCast(compute_pass);

    const binding = sdl.SDL_GPUTextureSamplerBinding{
        .texture = self.mTexture,
        .sampler = self.mSampler,
    };
    sdl.SDL_BindGPUComputeSamplers(sdl_compute_pass, 0, &binding, 1);
}

pub fn GetTexture(self: SGTextureManager) *sdl.SDL_GPUTexture {
    return self.mTexture.?;
}
pub fn GetSampler(self: SGTextureManager) *sdl.SDL_GPUSampler {
    return self.mSampler.?;
}

/// How much of the atlas is in use: the slots holding a texture, by size class, and the layers the array has
pub const Usage = struct {
    /// the bytes of every slot holding a texture
    UsedBytes: usize = 0,
    /// layers the array has now, and the most it may grow to
    Layers: usize = 0,
    MaxLayers: usize = 0,
    LayerBytes: usize = BYTES_PER_LAYER,
    Classes: [AtlasHandle.CLASS_COUNT]AtlasSlots.ClassUsage = undefined,
};

pub fn GetUsage(self: *SGTextureManager) Usage {
    var usage: Usage = .{ .Layers = self.mSlots.LayerCount(), .MaxLayers = self.mMaxLayers, .Classes = self.mSlots.Usage() };
    for (usage.Classes) |class| usage.UsedBytes += class.Used * class.SlotBytes;
    return usage;
}

const ReleaseOld = enum {
    /// let go of the old array straight away: nothing is being recorded
    Now,
    /// keep it until the frame being recorded is submitted (OnFrameEnd)
    AfterFrame,
};

/// Makes the array again with `layers` layers, copying every layer both have across on the GPU, and grows or shrinks the
/// slots' layers to match
fn Resize(self: *SGTextureManager, engine_context: *EngineContext, layers: usize, release_old: ReleaseOld) !void {
    const zone = Tracy.ZoneInit("SGTextureManager::Resize", @src());
    defer zone.Deinit();
    std.debug.assert(layers >= 1 and layers <= self.mMaxLayers);

    const texture_info = sdl.SDL_GPUTextureCreateInfo{
        .type = sdl.SDL_GPU_TEXTURETYPE_2D_ARRAY,
        .format = sdl.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
        .usage = sdl.SDL_GPU_TEXTUREUSAGE_SAMPLER | sdl.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET,
        .width = ATLAS_SIZE,
        .height = ATLAS_SIZE,
        .layer_count_or_depth = @intCast(layers),
        .num_levels = 1,
        .sample_count = sdl.SDL_GPU_SAMPLECOUNT_1,
        .props = 0,
    };
    //the atlas every texture and shown render target is copied into, shared by every world: the engine's
    const texture = engine_context.mGPUAllocator.CreateTexture(engine_context, &texture_info, GPUAllocator.ENGINE, "Texture atlas") orelse {
        std.log.err("TextureAtlasManager: SDL_CreateGPUTexture failed — {s}", .{sdl.SDL_GetError()});
        return error.InitFailed;
    };
    errdefer engine_context.mGPUAllocator.ReleaseTexture(engine_context, texture);

    const old_layers = self.mSlots.LayerCount();
    if (self.mTexture) |old| {
        const device: ?*sdl.SDL_GPUDevice = @ptrCast(engine_context.mRenderer.mPlatform.GetDevice());
        const cmd = sdl.SDL_AcquireGPUCommandBuffer(device) orelse return error.InitFailed;
        const copy_pass = sdl.SDL_BeginGPUCopyPass(cmd) orelse {
            _ = sdl.SDL_CancelGPUCommandBuffer(cmd);
            return error.InitFailed;
        };
        for (0..@min(old_layers, layers)) |layer| {
            const src = sdl.SDL_GPUTextureLocation{ .texture = old, .mip_level = 0, .layer = @intCast(layer), .x = 0, .y = 0, .z = 0 };
            const dst = sdl.SDL_GPUTextureLocation{ .texture = texture, .mip_level = 0, .layer = @intCast(layer), .x = 0, .y = 0, .z = 0 };
            sdl.SDL_CopyGPUTextureToTexture(copy_pass, &src, &dst, ATLAS_SIZE, ATLAS_SIZE, 1, false);
        }
        sdl.SDL_EndGPUCopyPass(copy_pass);
        _ = sdl.SDL_SubmitGPUCommandBuffer(cmd);

        switch (release_old) {
            .Now => engine_context.mGPUAllocator.ReleaseTexture(engine_context, old),
            .AfterFrame => try self.mRetired.append(engine_context.Keep(), old),
        }
    }
    self.mTexture = texture;

    if (layers > old_layers) {
        for (old_layers..layers) |_| try self.mSlots.AddLayer(engine_context.Keep());
    } else {
        self.mSlots.RemoveLayers(old_layers - layers);
    }
}

fn ReleaseRetired(self: *SGTextureManager, engine_context: *EngineContext) void {
    for (self.mRetired.items) |texture| engine_context.mGPUAllocator.ReleaseTexture(engine_context, texture);
    self.mRetired.clearRetainingCapacity();
}

fn UpdateToLayer(self: *SGTextureManager, engine_context: *EngineContext, device: ?*sdl.SDL_GPUDevice, pixels: *anyopaque, width: usize, height: usize, layer_index: u32, offset_x: u32, offset_y: u32) !void {
    const data_size = width * height * 4; //4 because RGBA8

    const transfer_info = sdl.SDL_GPUTransferBufferCreateInfo{
        .usage = sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = @intCast(data_size),
        .props = 0,
    };

    const transfer_buf = engine_context.mGPUAllocator.CreateTransferBuffer(engine_context, &transfer_info, GPUAllocator.ENGINE, "Texture atlas") orelse return error.UpdateFailed;
    defer engine_context.mGPUAllocator.ReleaseTransferBuffer(engine_context, transfer_buf);

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
        .pixels_per_row = @intCast(width),
        .rows_per_layer = @intCast(height),
    };

    const dst = sdl.SDL_GPUTextureRegion{
        .texture = self.mTexture,
        .mip_level = 0,
        .layer = layer_index,
        .x = offset_x,
        .y = offset_y,
        .z = 0,
        .w = @intCast(width),
        .h = @intCast(height),
        .d = 1,
    };

    sdl.SDL_UploadToGPUTexture(copy_pass, &src, &dst, false);
    sdl.SDL_EndGPUCopyPass(copy_pass);
    _ = sdl.SDL_SubmitGPUCommandBuffer(cmd);
}

/// The layer of the texture array a handle's texture is in
pub fn GetLayerIndex(texture_handle: u32) usize {
    return AtlasHandle.Layer(texture_handle);
}

/// Where in the texture array a texture's `local_uv` (0 to 1 across the texture) is: the UV in its layer, and the layer.
/// What the shaders do with a handle
pub fn GetTextureUV(texture_handle: u32, local_uv: Vec2(f32), tex_width: u32, tex_height: u32) Vec3(f32) {
    const atlas_size: f32 = @floatFromInt(ATLAS_SIZE);
    const offset_u = @as(f32, @floatFromInt(AtlasHandle.PixelX(texture_handle))) / atlas_size;
    const offset_v = @as(f32, @floatFromInt(AtlasHandle.PixelY(texture_handle))) / atlas_size;

    const scale_x: f32 = @as(f32, @floatFromInt(tex_width)) / atlas_size;
    const scale_y: f32 = @as(f32, @floatFromInt(tex_height)) / atlas_size;

    const uv_x = offset_u + local_uv.x * scale_x;
    const uv_y = offset_v + local_uv.y * scale_y;

    return .{ .x = uv_x, .y = uv_y, .z = @floatFromInt(AtlasHandle.Layer(texture_handle)) };
}

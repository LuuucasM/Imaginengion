//! The one place the engine's GPU memory is made and let go of: textures, buffers, transfer buffers and samplers, each
//! labelled with its owner (a world, or the engine for what every world shares) and counted per owner, the way the Keep
//! and Scratch allocators count CPU memory (Allocators.Counts). There is one, since there is one SDL device and what is
//! on it (the texture atlas, the renderer's buffers) is shared.
//!
//! SDL doesn't say how much memory what it makes takes, so the size is worked out from what was asked for: a texture's
//! texels (SDL_CalculateGPUTextureFormatSize) for every level and sample, a buffer's size. The driver can round these up
//! and adds its own bookkeeping, so the real use is a bit more. Samplers take no memory to speak of, and are only counted.
//!
//! Main thread only, like the renderer. Engine code only: a script DLL can't reach SDL.
const std = @import("std");
const sdl = @import("CImports.zig").sdl;
const EngineContext = @import("EngineContext.zig");
const Profiler = @import("Profiler.zig");

const GPUAllocator = @This();

/// Who a GPU resource is for: a world, numbered as EngineContext.WorldTag numbers them, or ENGINE
pub const Owner = Profiler.World;
pub const ENGINE: Owner = Profiler.NO_WORLD;
pub const OWNER_COUNT = EngineContext.WORLD_NAMES.len + 1;

/// What one owner holds on the GPU now
pub const Counts = struct {
    Bytes: u64 = 0,
    /// the most it held at once
    Peak: u64 = 0,
    Textures: u32 = 0,
    Buffers: u32 = 0,
    /// transfer buffers, which carry uploads and are usually let go of straight after
    TransferBuffers: u32 = 0,
    Samplers: u32 = 0,
};

const Kind = enum { Texture, Buffer, TransferBuffer, Sampler };

/// What a resource made here is: who it is for and how big it was worked out to be, so letting go of it needs neither
const Record = struct {
    mOwner: Owner,
    mBytes: u64,
    mKind: Kind,
};

/// Each owner's counts, at its Owner number
mCounts: [OWNER_COUNT]Counts = @splat(.{}),
/// Every resource made here and not yet let go of, by its address
mRecords: std.AutoHashMapUnmanaged(usize, Record) = .empty,

/// Lets go of the records. Anything still held then was never released, and is logged
pub fn Deinit(self: *GPUAllocator, keep_allocator: std.mem.Allocator) void {
    if (self.mRecords.count() > 0) std.log.err("{d} GPU resource(s) were never released", .{self.mRecords.count()});
    self.mRecords.deinit(keep_allocator);
    self.* = .{};
}

pub fn CountsOf(self: *const GPUAllocator, owner: Owner) Counts {
    return self.mCounts[owner];
}

pub fn CreateTexture(self: *GPUAllocator, engine_context: *EngineContext, info: *const sdl.SDL_GPUTextureCreateInfo, owner: Owner) ?*sdl.SDL_GPUTexture {
    const texture = sdl.SDL_CreateGPUTexture(Device(engine_context), info) orelse return null;
    self.Made(engine_context, texture, .Texture, TextureBytes(info), owner) catch {
        sdl.SDL_ReleaseGPUTexture(Device(engine_context), texture);
        return null;
    };
    return texture;
}

pub fn ReleaseTexture(self: *GPUAllocator, engine_context: *EngineContext, texture: *sdl.SDL_GPUTexture) void {
    self.Gone(texture);
    sdl.SDL_ReleaseGPUTexture(Device(engine_context), texture);
}

pub fn CreateBuffer(self: *GPUAllocator, engine_context: *EngineContext, info: *const sdl.SDL_GPUBufferCreateInfo, owner: Owner) ?*sdl.SDL_GPUBuffer {
    const buffer = sdl.SDL_CreateGPUBuffer(Device(engine_context), info) orelse return null;
    self.Made(engine_context, buffer, .Buffer, info.size, owner) catch {
        sdl.SDL_ReleaseGPUBuffer(Device(engine_context), buffer);
        return null;
    };
    return buffer;
}

pub fn ReleaseBuffer(self: *GPUAllocator, engine_context: *EngineContext, buffer: *sdl.SDL_GPUBuffer) void {
    self.Gone(buffer);
    sdl.SDL_ReleaseGPUBuffer(Device(engine_context), buffer);
}

pub fn CreateTransferBuffer(self: *GPUAllocator, engine_context: *EngineContext, info: *const sdl.SDL_GPUTransferBufferCreateInfo, owner: Owner) ?*sdl.SDL_GPUTransferBuffer {
    const buffer = sdl.SDL_CreateGPUTransferBuffer(Device(engine_context), info) orelse return null;
    self.Made(engine_context, buffer, .TransferBuffer, info.size, owner) catch {
        sdl.SDL_ReleaseGPUTransferBuffer(Device(engine_context), buffer);
        return null;
    };
    return buffer;
}

pub fn ReleaseTransferBuffer(self: *GPUAllocator, engine_context: *EngineContext, buffer: *sdl.SDL_GPUTransferBuffer) void {
    self.Gone(buffer);
    sdl.SDL_ReleaseGPUTransferBuffer(Device(engine_context), buffer);
}

pub fn CreateSampler(self: *GPUAllocator, engine_context: *EngineContext, info: *const sdl.SDL_GPUSamplerCreateInfo, owner: Owner) ?*sdl.SDL_GPUSampler {
    const sampler = sdl.SDL_CreateGPUSampler(Device(engine_context), info) orelse return null;
    self.Made(engine_context, sampler, .Sampler, 0, owner) catch {
        sdl.SDL_ReleaseGPUSampler(Device(engine_context), sampler);
        return null;
    };
    return sampler;
}

pub fn ReleaseSampler(self: *GPUAllocator, engine_context: *EngineContext, sampler: *sdl.SDL_GPUSampler) void {
    self.Gone(sampler);
    sdl.SDL_ReleaseGPUSampler(Device(engine_context), sampler);
}

/// How many bytes a texture made from `info` takes: each level's texels, half as wide and high as the one before, for
/// every layer (or depth slice) and every sample
pub fn TextureBytes(info: *const sdl.SDL_GPUTextureCreateInfo) u64 {
    const samples: u64 = @as(u64, 1) << @intCast(info.sample_count);
    const layers = if (info.type == sdl.SDL_GPU_TEXTURETYPE_CUBE) info.layer_count_or_depth * 6 else info.layer_count_or_depth;
    var total: u64 = 0;
    for (0..@max(1, info.num_levels)) |level| {
        const width = @max(1, info.width >> @intCast(level));
        const height = @max(1, info.height >> @intCast(level));
        total += sdl.SDL_CalculateGPUTextureFormatSize(info.format, width, height, layers);
    }
    return total * samples;
}

/// Records a resource just made, and counts it on its owner. Only fails for want of memory for the record
fn Made(self: *GPUAllocator, engine_context: *EngineContext, resource: *anyopaque, kind: Kind, bytes: u64, owner: Owner) !void {
    std.debug.assert(owner < OWNER_COUNT);
    try self.mRecords.put(engine_context.Keep(), @intFromPtr(resource), .{ .mOwner = owner, .mBytes = bytes, .mKind = kind });
    const counts = &self.mCounts[owner];
    counts.Bytes += bytes;
    counts.Peak = @max(counts.Peak, counts.Bytes);
    switch (kind) {
        .Texture => counts.Textures += 1,
        .Buffer => counts.Buffers += 1,
        .TransferBuffer => counts.TransferBuffers += 1,
        .Sampler => counts.Samplers += 1,
    }
}

/// A resource is being let go of: off its owner's counts. One not made here is let go of all the same, uncounted
fn Gone(self: *GPUAllocator, resource: *anyopaque) void {
    const record = (self.mRecords.fetchRemove(@intFromPtr(resource)) orelse return).value;
    const counts = &self.mCounts[record.mOwner];
    counts.Bytes -= record.mBytes;
    switch (record.mKind) {
        .Texture => counts.Textures -= 1,
        .Buffer => counts.Buffers -= 1,
        .TransferBuffer => counts.TransferBuffers -= 1,
        .Sampler => counts.Samplers -= 1,
    }
}

fn Device(engine_context: *EngineContext) *sdl.SDL_GPUDevice {
    return @ptrCast(@alignCast(engine_context.mRenderer.mPlatform.GetDevice()));
}

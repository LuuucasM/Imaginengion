const std = @import("std");
const sdl = @import("../Core/CImports.zig").sdl;
const Stage = @import("../Assets/Assets/ShaderAsset.zig").Stage;
const EngineContext = @import("../Core/EngineContext.zig");
const SDLSSBO = @This();

mSize: usize,
mSlot: usize,
mStage: Stage,
mBuffer: ?*sdl.SDL_GPUBuffer,
mTransferBuff: ?*sdl.SDL_GPUTransferBuffer,
mTransferSize: usize,

pub const empty: SDLSSBO = .{
    .mBuffer = null,
    .mStage = undefined,
    .mSize = undefined,
    .mSlot = undefined,
    .mTransferBuff = null,
    .mTransferSize = 0,
};

pub fn Init(self: *SDLSSBO, engine_context: *EngineContext, size: usize, slot: usize, stage: Stage) void {
    self.mSize = size;
    self.mSlot = slot;
    self.mStage = stage;

    if (size == 0) return;

    const device: *sdl.SDL_GPUDevice = @ptrCast(@alignCast(engine_context.mRenderer.mPlatform.GetDevice()));
    self.mBuffer = CreateBuffer(device, size);
    self.mTransferBuff = CreateTransferBuffer(device, size);
}

pub fn Deinit(self: *SDLSSBO, engine_context: *EngineContext) void {
    const device: *sdl.SDL_GPUDevice = @ptrCast(@alignCast(engine_context.mRenderer.mPlatform.GetDevice()));
    if (self.mBuffer) |buf| {
        sdl.SDL_ReleaseGPUBuffer(device, buf);
        self.mBuffer = null;
    }
    if (self.mTransferBuff) |tb| {
        sdl.SDL_ReleaseGPUTransferBuffer(device, tb);
        self.mTransferBuff = null;
    }
}

pub fn Bind(self: SDLSSBO, pass: *anyopaque) void {
    if (self.mBuffer == null) return;
    switch (self.mStage) {
        .Vertex => sdl.SDL_BindGPUVertexStorageBuffers(@ptrCast(@alignCast(pass)), @intCast(self.mSlot), &self.mBuffer, 1),
        .Fragment => sdl.SDL_BindGPUFragmentStorageBuffers(@ptrCast(@alignCast(pass)), @intCast(self.mSlot), &self.mBuffer, 1),
        .Compute => sdl.SDL_BindGPUComputeStorageBuffers(@ptrCast(@alignCast(pass)), @intCast(self.mSlot), &self.mBuffer, 1),
    }
}

pub fn SetData(self: *SDLSSBO, engine_context: *EngineContext, data: *const anyopaque, size: usize, offset: u32) bool {
    if (size == 0) return false;

    var resize: bool = false;
    const device: *sdl.SDL_GPUDevice = @ptrCast(@alignCast(engine_context.mRenderer.mPlatform.GetDevice()));
    const cmd: *sdl.SDL_GPUCommandBuffer = @ptrCast(@alignCast(engine_context.mRenderer.mPlatform.GetWorkCmdBuff()));

    if (size + offset > self.mSize) {
        if (self.mBuffer) |buf| sdl.SDL_ReleaseGPUBuffer(device, buf);
        self.mSize = size + offset;
        self.mBuffer = CreateBuffer(device, self.mSize);
        resize = true;
    }

    if (size > self.mTransferSize) {
        if (self.mTransferBuff) |tb| sdl.SDL_ReleaseGPUTransferBuffer(device, tb);
        self.mTransferSize = size;
        self.mTransferBuff = CreateTransferBuffer(device, size);
    }

    const mapped = sdl.SDL_MapGPUTransferBuffer(device, self.mTransferBuff, true);
    std.debug.assert(mapped != null);
    @memcpy(
        @as([*]u8, @ptrCast(mapped))[0..size],
        @as([*]const u8, @ptrCast(data))[0..size],
    );
    sdl.SDL_UnmapGPUTransferBuffer(device, self.mTransferBuff);

    const copy_pass = sdl.SDL_BeginGPUCopyPass(cmd);
    std.debug.assert(copy_pass != null);

    const src = sdl.SDL_GPUTransferBufferLocation{
        .transfer_buffer = self.mTransferBuff,
        .offset = 0,
    };
    const dst = sdl.SDL_GPUBufferRegion{
        .buffer = self.mBuffer,
        .offset = offset,
        .size = @intCast(size),
    };
    sdl.SDL_UploadToGPUBuffer(copy_pass, &src, &dst, false);
    sdl.SDL_EndGPUCopyPass(copy_pass);

    return resize;
}

pub fn GetBuffer(self: SDLSSBO) *sdl.SDL_GPUBuffer {
    std.debug.assert(self.mBuffer != null);
    return self.mBuffer.?;
}

pub fn GetBinding(self: SDLSSBO) usize {
    return self.mSlot;
}

fn CreateBuffer(device: *sdl.SDL_GPUDevice, size: usize) ?*sdl.SDL_GPUBuffer {
    const buffer_info = sdl.SDL_GPUBufferCreateInfo{
        .usage = sdl.SDL_GPU_BUFFERUSAGE_GRAPHICS_STORAGE_READ,
        .size = @intCast(size),
        .props = 0,
    };
    const buffer = sdl.SDL_CreateGPUBuffer(device, &buffer_info);
    std.debug.assert(buffer != null);
    return buffer;
}

fn CreateTransferBuffer(device: *sdl.SDL_GPUDevice, size: usize) ?*sdl.SDL_GPUTransferBuffer {
    const info = sdl.SDL_GPUTransferBufferCreateInfo{
        .usage = sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = @intCast(size),
        .props = 0,
    };
    const buffer = sdl.SDL_CreateGPUTransferBuffer(device, &info);
    std.debug.assert(buffer != null);
    return buffer;
}

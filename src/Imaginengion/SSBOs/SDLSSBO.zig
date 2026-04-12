const std = @import("std");
const sdl = @import("../Core/CImports.zig").sdl;
const Stage = @import("../Assets/Assets/ShaderAsset.zig").Stage;
const EngineContext = @import("../Core/EngineContext.zig");
const SDLSSBO = @This();

mSize: usize,
mSlot: u32,
mStage: Stage,
mBuffer: ?*sdl.SDL_GPUBuffer,

pub const empty: SDLSSBO = .{
    .mBuffer = null,
    .mStage = undefined,
    .mSize = undefined,
    .mSlot = undefined,
};

pub fn Init(self: *SDLSSBO, engine_context: *EngineContext, size: usize, slot: u32, stage: Stage) void {
    self.mSize = size;
    self.mSlot = slot;
    self.mStage = stage;

    const device: *sdl.SDL_GPUDevice = @ptrCast(@alignCast(engine_context.mRenderer.mRenderContext.GetDevice()));

    self.mBuffer = CreateBuffer(device, size);
}

pub fn Deinit(self: *SDLSSBO, engine_context: *EngineContext) void {
    std.debug.assert(self.mBuffer != null);

    const device: *sdl.SDL_GPUDevice = @ptrCast(@alignCast(engine_context.mRenderer.mRenderContext.GetDevice()));

    sdl.SDL_ReleaseGPUBuffer(device, self.mBuffer);
    self.mBuffer = null;
}

pub fn Bind(self: *SDLSSBO, render_pass: *anyopaque) void {
    std.debug.assert(self.mBuffer != null);
    const pass: *sdl.SDL_GPURenderPass = @ptrCast(@alignCast(render_pass));

    switch (self.mStage) {
        .Vertex => sdl.SDL_BindGPUVertexStorageBuffers(pass, self.mSlot, &self.mBuffer, 1),
        .Fragment => sdl.SDL_BindGPUFragmentStorageBuffers(pass, self.mSlot, &self.mBuffer, 1),
    }
}

pub fn SetData(self: SDLSSBO, engine_context: *EngineContext, data: *const anyopaque, size: usize, offset: u32) void {
    std.debug.assert(self.mBuffer != null);

    const device: *sdl.SDL_GPUDevice = @ptrCast(@alignCast(engine_context.mRenderer.mRenderContext.GetDevice()));
    const cmd: *sdl.SDL_GPUCommandBuffer = @ptrCast(@alignCast(engine_context.mRenderer.mRenderContext.GetCommandBuff()));

    if (size + offset > self.mSize) {
        sdl.SDL_ReleaseGPUBuffer(device, self.mBuffer.?);
        self.mSize = size + offset;
        self.mBuffer = CreateBuffer(device, self.mSize);
    }

    const transfer_info = sdl.SDL_GPUTransferBufferCreateInfo{
        .usage = sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = @intCast(size),
        .props = 0,
    };
    const transfer_buf = sdl.SDL_CreateGPUTransferBuffer(device, &transfer_info);
    std.debug.assert(transfer_buf != null);
    defer sdl.SDL_ReleaseGPUTransferBuffer(device, transfer_buf);

    const mapped = sdl.SDL_MapGPUTransferBuffer(device, transfer_buf, false);
    std.debug.assert(mapped != null);
    @memcpy(
        @as([*]u8, @ptrCast(mapped))[0..size],
        @as([*]const u8, @ptrCast(data))[0..size],
    );
    sdl.SDL_UnmapGPUTransferBuffer(device, transfer_buf);

    const copy_pass = sdl.SDL_BeginGPUCopyPass(cmd);
    std.debug.assert(copy_pass != null);

    const src = sdl.SDL_GPUTransferBufferLocation{
        .transfer_buffer = transfer_buf,
        .offset = 0,
    };
    const dst = sdl.SDL_GPUBufferRegion{
        .buffer = self.mBuffer,
        .offset = offset,
        .size = @intCast(size),
    };
    sdl.SDL_UploadToGPUBuffer(copy_pass, &src, &dst, false);
    sdl.SDL_EndGPUCopyPass(copy_pass);
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

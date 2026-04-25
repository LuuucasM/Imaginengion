const std = @import("std");
const builtin = @import("builtin");
const Window = @import("../../Windows/Window.zig");
const Vec4f32 = @import("../../Math/LinAlg.zig").Vec4f32;
const ShaderAsset = @import("../../Assets/Assets.zig").ShaderAsset;
const EngineContext = @import("../../Core/EngineContext.zig");
const PushConstants = @import("../RenderPlatform.zig").PushConstants;
const StorageBufferBinding = @import("../RenderPlatform.zig").StorageBufferBinding;

const sdl = @import("../../Core/CImports.zig").sdl;

const SDLPlatform = @This();

mDevice: *sdl.SDL_GPUDevice = undefined,
mCurrentCmdBuffer: ?*sdl.SDL_GPUCommandBuffer = null,

pub fn Init(self: *SDLPlatform, engine_context: *EngineContext, shader: *ShaderAsset) void {
    const sdl_window: ?*sdl.SDL_Window = @ptrCast(engine_context.mAppWindow.GetNativeWindow());

    self.mDevice = sdl.SDL_CreateGPUDevice(sdl.SDL_GPU_SHADERFORMAT_SPIRV, builtin.mode == .Debug, null) orelse unreachable;

    const claimed = sdl.SDL_ClaimWindowForGPUDevice(self.mDevice, sdl_window);
    std.debug.assert(claimed);

    std.log.info("SDL_GPU Info:", .{});
    std.log.info("\tDriver: {s}", .{sdl.SDL_GetGPUDeviceDriver(self.mDevice)});

    self.mRenderInterop.Init(self.mDevice);
    try self.mRenderBindlessReg.Init(engine_context.EngineAllocator(), &self.mRenderInterop);
    self.mSDFPipeline.Init(&self.mRenderInterop, &self.mRenderBindlessReg, shader);
}

pub fn Deinit(self: *SDLPlatform, engine_context: *EngineContext) void {
    const sdl_window: ?*sdl.SDL_Window = @ptrCast(engine_context.mAppWindow.GetNativeWindow());

    sdl.SDL_WaitForGPUIdle(self.mDevice);

    sdl.SDL_ReleaseWindowFromGPUDevice(self.mDevice, sdl_window);
    sdl.SDL_DestroyGPUDevice(self.mDevice);
}

pub fn BeginFrame(self: SDLPlatform, window: *Window) bool {
    self.mCurrentCmdBuffer = sdl.SDL_AcquireGPUCommandBuffer(self.mDevice);
    std.debug.assert(self.mCurrentCmdBuffer != null);

    var swapchain_tex: ?sdl.SDL_GPUTexture = null;
    var width: usize = 0;
    var height: usize = 0;
    const acquired = sdl.SDL_AcquireGPUSwapchainTexture(
        self.mCurrentCmdBuffer,
        window.GetNativeWindow(),
        &swapchain_tex,
        &width,
        &height,
    );

    if (!acquired or swapchain_tex == null) {
        _ = sdl.SDL_CancelGPUCommandBuffer(self.mCurrentCmdBuffer);
        self.mCurrentCmdBuffer = null;
        return false;
    }

    return true;
}

pub fn EndFrame(self: *SDLPlatform) void {
    std.debug.assert(self.mCurrentCmdBuffer != null);

    _ = sdl.SDL_SubmitGPUCommandBuffer(self.mCurrentCmdBuffer);

    self.mCurrentCmdBuffer = null;
}

pub fn GetDevice(self: SDLPlatform) *sdl.SDL_GPUDevice {
    return self.mDevice.?;
}

pub fn GetCommandBuff(self: SDLPlatform) *sdl.SDL_GPUCommandBuffer {
    std.debug.assert(self.mCurrentCmdBuffer != null);
    return self.mCurrentCmdBuffer.?;
}

pub fn PushDebugGroup(self: SDLPlatform, message: []const u8) void {
    std.debug.assert(self.mCurrentCmdBuffer != null);
    sdl.SDL_PushGPUDebugGroup(self.mCurrentCmdBuffer, message.ptr);
}

pub fn PopDebugGroup(self: SDLPlatform) void {
    std.debug.assert(self.mCurrentCmdBuffer != null);
    sdl.SDL_PopGPUDebugGroup(self.mCurrentCmdBuffer);
}

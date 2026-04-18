const std = @import("std");
const builtin = @import("builtin");
const Window = @import("../../Windows/Window.zig");
const Vec4f32 = @import("../../Math/LinAlg.zig").Vec4f32;
const RenderInterop = @import("RenderInterop.zig");
const RenderBindlessReg = @import("RenderBindlessReg.zig");
const SDLTexture2D = @import("../../Assets/Assets/Texture2Ds/SDLTexture2D.zig");
const SDFPipeline = @import("SDFPipeline.zig");
const ShaderAsset = @import("../../Assets/Assets.zig").ShaderAsset;
const EngineContext = @import("../../Core/EngineContext.zig");
const PushConstants = @import("../RenderPlatform.zig").PushConstants;

const sdl = @import("../../Core/CImports.zig").sdl;

const SDLPlatform = @This();

mDevice: ?*sdl.SDL_GPUDevice = null,
mCurrentCmdBuffer: ?*sdl.SDL_GPUCommandBuffer = null,
mRenderInterop: RenderInterop = .{},
mRenderBindlessReg: RenderBindlessReg = .{},
mSDFPipeline: SDFPipeline = .{},

pub fn Init(self: *SDLPlatform, engine_context: *EngineContext, shader: *ShaderAsset) void {
    std.debug.assert(self.mDevice == null);

    const sdl_window: ?*sdl.SDL_Window = @ptrCast(engine_context.mAppWindow.GetNativeWindow());

    self.mDevice = sdl.SDL_CreateGPUDevice(sdl.SDL_GPU_SHADERFORMAT_SPIRV, builtin.mode == .Debug, null);
    std.debug.assert(self.mDevice != null);

    const claimed = sdl.SDL_ClaimWindowForGPUDevice(self.mDevice, sdl_window);
    std.debug.assert(claimed);

    std.log.info("SDL_GPU Info:", .{});
    std.log.info("\tDriver: {s}", .{sdl.SDL_GetGPUDeviceDriver(self.mDevice)});

    self.mRenderInterop.Init(self.mDevice);
    self.mRenderBindlessReg.Init(engine_context.EngineAllocator(), &self.mRenderInterop);
    self.mSDFPipeline.Init(&self.mRenderInterop, &self.mRenderBindlessReg, shader);
}

pub fn Deinit(self: *SDLPlatform, engine_context: *EngineContext) void {
    const sdl_window: ?*sdl.SDL_Window = @ptrCast(engine_context.mAppWindow.GetNativeWindow());

    sdl.SDL_WaitForGPUIdle(self.mDevice);

    self.mSDFPipeline.Deinit(self.mRenderInterop);
    self.mRenderBindlessReg.Deinit(engine_context.EngineAllocator());

    sdl.SDL_ReleaseWindowFromGPUDevice(self.mDevice, sdl_window);
    sdl.SDL_DestroyGPUDevice(self.mDevice);

    self.mDevice = null;
}

pub fn BeginFrame(self: SDLPlatform, window: *Window) bool {
    std.debug.assert(self.mDevice != null);
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
    std.debug.assert(self.mDevice != null);
    return self.mDevice.?;
}

pub fn GetCommandBuff(self: SDLPlatform) *sdl.SDL_GPUCommandBuffer {
    std.debug.assert(self.mCurrentCmdBuffer != null);
    return self.mCurrentCmdBuffer.?;
}

pub fn RegisterTexture2D(self: SDLPlatform, texture_2d: *anyopaque, texture_format: u32) u32 {
    const sdl_texture2d: *SDLTexture2D = @ptrCast(texture_2d);
    self.mRenderBindlessReg.RegisterTexture2D(&self.mRenderInterop, sdl_texture2d, texture_format);
}

pub fn Unregister(self: SDLPlatform, slot: u32) void {
    self.mRenderBindlessReg.Unregister(&self.mRenderInterop, slot);
}

pub fn Draw(self: *SDLPlatform, cmd: *anyopaque, push_constants: anytype) void {
    const sdl_cmd: *sdl.SDL_GPUCommandBuffer = @ptrCast(cmd);
    self.mSDFPipeline.Draw(sdl_cmd, push_constants);
}

pub fn PushDebugGroup(self: SDLPlatform, message: []const u8) void {
    std.debug.assert(self.mCurrentCmdBuffer != null);
    sdl.SDL_PushGPUDebugGroup(self.mCurrentCmdBuffer, message.ptr);
}

pub fn PopDebugGroup(self: SDLPlatform) void {
    std.debug.assert(self.mCurrentCmdBuffer != null);
    sdl.SDL_PopGPUDebugGroup(self.mCurrentCmdBuffer);
}

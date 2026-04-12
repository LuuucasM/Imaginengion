const std = @import("std");
const builtin = @import("builtin");
const Application = @import("../Core/Application.zig");
const VertexArray = @import("../VertexArrays/VertexArray.zig");
const Window = @import("../Windows/Window.zig");
const Vec4f32 = @import("../Math/LinAlg.zig").Vec4f32;

const sdl = @import("../Core/CImports.zig").sdl;

const SDLContext = @This();

mDevice: ?*sdl.SDL_GPUDevice = null,
mCurrentCmdBuffer: ?*sdl.SDL_GPUCommandBuffer = null,
mCurrentRenderPass: ?*sdl.SDL_GPURenderPass = null,

pub fn Init(self: *SDLContext, window: *Window) void {
    std.debug.assert(self.mDevice == null);

    const sdl_window: ?*sdl.SDL_Window = @ptrCast(window.GetNativeWindow());

    self.mDevice = sdl.SDL_CreateGPUDevice(sdl.SDL_GPU_SHADERFORMAT_SPIRV, builtin.mode == .Debug, null);
    std.debug.assert(self.mDevice != null);

    const claimed = sdl.SDL_ClaimWindowForGPUDevice(self.mDevice, sdl_window);
    std.debug.assert(claimed);

    std.log.info("SDL_GPU Info:", .{});
    std.log.info("\tDriver: {s}", .{sdl.SDL_GetGPUDeviceDriver(self.mDevice)});
}

pub fn Deinit(self: *SDLContext, window: *Window) void {
    const sdl_window: ?*sdl.SDL_Window = @ptrCast(window.GetNativeWindow());

    sdl.SDL_WaitForGPUIdle(self.mDevice);
    sdl.SDL_ReleaseWindowFromGPUDevice(self.mDevice, sdl_window);
    sdl.SDL_DestroyGPUDevice(self.mDevice);

    self.mDevice = null;
}

pub fn BeginFrame(self: SDLContext, window: *Window, clear_color: Vec4f32) bool {
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

    const color_target = sdl.SDL_GPUColorTargetInfo{
        .texture = swapchain_tex,
        .mip_level = 0,
        .layer_or_depth_plane = 0,
        .clear_color = .{
            .r = clear_color[0],
            .g = clear_color[1],
            .b = clear_color[2],
            .a = clear_color[3],
        },
        .load_op = sdl.SDL_GPU_LOADOP_CLEAR,
        .store_op = sdl.SDL_GPU_STOREOP_STORE,
        .resolve_texture = null,
        .resolve_layer = 0,
        .cycle = false,
        .cycle_resolve_texture = false,
        .padding1 = 0,
        .padding2 = 0,
    };
    self.mCurrentRenderPass = sdl.SDL_BeginGPURenderPass(self.mCurrentCmdBuffer, &color_target, 1, null);

    std.debug.assert(self.mCurrentRenderPass != null);

    return true;
}

pub fn EndFrame(self: *SDLContext) void {
    std.debug.assert(self.mCurrentRenderPass != null);
    std.debug.assert(self.mCurrentCmdBuffer != null);

    sdl.SDL_EndGPURenderPass(self.mCurrentRenderPass);
    _ = sdl.SDL_SubmitGPUCommandBuffer(self.mCurrentCmdBuffer);

    self.mCurrentRenderPass = null;
    self.mCurrentCmdBuffer = null;
}

pub fn GetMaxTextureImageSlots(_: SDLContext) usize {
    //TODO: have to query the physical device, not built into SDL
    return 64;
}

pub fn GetDevice(self: SDLContext) *anyopaque {
    std.debug.assert(self.mDevice != null);
    return self.mDevice.?;
}

pub fn GetRenderPass(self: SDLContext) *anyopaque {
    std.debug.assert(self.mCurrentRenderPass != null);
    return self.mCurrentRenderPass.?;
}

pub fn GetCommandBuff(self: SDLContext) *anyopaque {
    std.debug.assert(self.mCurrentCmdBuffer != null);
    return self.mCurrentCmdBuffer.?;
}

pub fn Draw(self: *SDLContext) void {
    std.debug.assert(self.mCurrentRenderPass != null);
    sdl.SDL_DrawGPUPrimitives(self.mCurrentRenderPass, 3, 1, 0, 0);
}

pub fn PushDebugGroup(self: SDLContext, message: []const u8) void {
    std.debug.assert(self.mCurrentCmdBuffer != null);
    sdl.SDL_PushGPUDebugGroup(self.mCurrentCmdBuffer, message.ptr);
}

pub fn PopDebugGroup(self: SDLContext) void {
    std.debug.assert(self.mCurrentCmdBuffer != null);
    sdl.SDL_PopGPUDebugGroup(self.mCurrentCmdBuffer);
}

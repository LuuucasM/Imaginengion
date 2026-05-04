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

pub fn Init(self: *SDLPlatform, engine_context: *EngineContext) void {
    const sdl_window: ?*sdl.SDL_Window = @ptrCast(engine_context.mAppWindow.GetNativeWindow());

    const vk_api_1_3_0: u32 = (0 << 29) | (1 << 22) | (3 << 12) | 0;
    var vulkan_options = sdl.SDL_GPUVulkanOptions{
        .vulkan_api_version = vk_api_1_3_0,
        .feature_list = null,
        .vulkan_10_physical_device_features = null,
        .device_extension_count = 0,
        .device_extension_names = null,
        .instance_extension_count = 0,
        .instance_extension_names = null,
    };

    const props = sdl.SDL_CreateProperties();
    defer sdl.SDL_DestroyProperties(props);

    _ = sdl.SDL_SetPointerProperty(props, sdl.SDL_PROP_GPU_DEVICE_CREATE_VULKAN_OPTIONS_POINTER, &vulkan_options);
    _ = sdl.SDL_SetBooleanProperty(props, sdl.SDL_PROP_GPU_DEVICE_CREATE_DEBUGMODE_BOOLEAN, true);
    _ = sdl.SDL_SetBooleanProperty(props, sdl.SDL_PROP_GPU_DEVICE_CREATE_SHADERS_SPIRV_BOOLEAN, true);

    self.mDevice = sdl.SDL_CreateGPUDeviceWithProperties(props) orelse unreachable;

    const claimed = sdl.SDL_ClaimWindowForGPUDevice(self.mDevice, sdl_window);
    std.debug.assert(claimed);

    std.log.info("SDL_GPU Info:", .{});
    std.log.info("\tDriver: {s}", .{sdl.SDL_GetGPUDeviceDriver(self.mDevice)});
}

pub fn Deinit(self: *SDLPlatform, window: *Window) void {
    const sdl_window: ?*sdl.SDL_Window = @ptrCast(window.GetNativeWindow());

    _ = sdl.SDL_WaitForGPUIdle(self.mDevice);
    _ = if (self.mCurrentCmdBuffer) |cmd| sdl.SDL_CancelGPUCommandBuffer(cmd);
    sdl.SDL_ReleaseWindowFromGPUDevice(self.mDevice, sdl_window);
    sdl.SDL_DestroyGPUDevice(self.mDevice);
}

pub fn BeginFrame(self: *SDLPlatform, window: *Window) bool {
    std.debug.assert(self.mCurrentCmdBuffer == null);
    self.mCurrentCmdBuffer = sdl.SDL_AcquireGPUCommandBuffer(self.mDevice);
    std.debug.assert(self.mCurrentCmdBuffer != null);

    var swapchain_tex: ?*sdl.SDL_GPUTexture = null;
    var width: usize = 0;
    var height: usize = 0;

    const sdl_window: *sdl.SDL_Window = @ptrCast(window.GetNativeWindow());

    const acquired = sdl.SDL_AcquireGPUSwapchainTexture(
        self.mCurrentCmdBuffer,
        sdl_window,
        @ptrCast(&swapchain_tex),
        @ptrCast(&width),
        @ptrCast(&height),
    );

    if (!acquired) {
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
    return self.mDevice;
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

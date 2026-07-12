const std = @import("std");
const builtin = @import("builtin");
const Window = @import("../../Windows/Window.zig");
const ShaderAsset = @import("../../Assets/Assets.zig").ShaderAsset;
const EngineContext = @import("../../Core/EngineContext.zig");
const PushConstants = @import("../RenderPlatform.zig").PushConstants;
const ComputeOutput = @import("../Renderer.zig").ComputeOutput;
const StorageBufferBinding = @import("../RenderPlatform.zig").StorageBufferBinding;

const sdl = @import("../../Core/CImports.zig").sdl;

const SDLPlatform = @This();

mDevice: *sdl.SDL_GPUDevice = undefined,
mCurrentCmdBuffer: ?*sdl.SDL_GPUCommandBuffer = null,
mSwapchainTexture: ?*sdl.SDL_GPUTexture = null,
mSwapchainWidth: u32 = 0,
mSwapchainHeight: u32 = 0,

pub fn Init(self: *SDLPlatform, engine_context: *EngineContext) void {
    const sdl_window: ?*sdl.SDL_Window = @ptrCast(engine_context.mAppWindow.GetNativeWindow());
    const vk_api_1_3_0: u32 = (0 << 29) | (1 << 22) | (3 << 12) | 0;

    var features_1_0 = sdl.VkPhysicalDeviceFeatures{
        .shaderInt16 = sdl.VK_TRUE,
    };

    var features_1_2 = sdl.VkPhysicalDeviceVulkan12Features{
        .sType = sdl.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
        .pNext = null,
        .shaderInt8 = sdl.VK_TRUE,
    };

    var features_1_1 = sdl.VkPhysicalDeviceVulkan11Features{
        .sType = sdl.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
        .pNext = &features_1_2,
        .variablePointersStorageBuffer = sdl.VK_TRUE,
        .variablePointers = sdl.VK_TRUE,
    };

    var vulkan_options = sdl.SDL_GPUVulkanOptions{
        .vulkan_api_version = vk_api_1_3_0,
        .feature_list = &features_1_1,
        .vulkan_10_physical_device_features = &features_1_0,
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

    self.mSwapchainTexture = swapchain_tex;
    self.mSwapchainWidth = width;
    self.mSwapchainHeight = height;

    return true;
}

pub fn HasFrame(self: SDLPlatform) bool {
    if (self.mCurrentCmdBuffer != null and self.mSwapchainTexture != null) {
        return true;
    }
    return false;
}

pub fn EndFrame(self: *SDLPlatform) void {
    std.debug.assert(self.mCurrentCmdBuffer != null);

    _ = sdl.SDL_SubmitGPUCommandBuffer(self.mCurrentCmdBuffer);

    self.mCurrentCmdBuffer = null;
}

pub fn Present(self: SDLPlatform, compute_texture: *ComputeOutput) void {
    const blit_info = sdl.SDL_GPUBlitInfo{
        .source = .{
            .texture = compute_texture.GetTexture(),
            .mip_level = 0,
            .layer_or_depth_plane = 0,
            .x = 0,
            .y = 0,
            .w = @intCast(compute_texture.GetWidth()),
            .h = @intCast(compute_texture.GetHeight()),
        },
        .destination = .{
            .texture = self.mSwapchainTexture.?,
            .mip_level = 0,
            .layer_or_depth_plane = 0,
            .x = 0,
            .y = 0,
            .w = self.mPlatform.mSwapchainWidth,
            .h = self.mPlatform.mSwapchainHeight,
        },
        .load_op = sdl.SDL_GPU_LOADOP_DONT_CARE,
        .clear_color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
        .flip_mode = sdl.SDL_FLIP_NONE,
        .filter = sdl.SDL_GPU_FILTER_NEAREST,
        .cycle = false,
    };
    sdl.SDL_BlitGPUTexture(self.mCurrentCmdBuffer.?, &blit_info);
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

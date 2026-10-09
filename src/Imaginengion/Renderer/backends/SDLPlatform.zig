const std = @import("std");
const builtin = @import("builtin");
const Window = @import("../../Windows/Window.zig");
const ShaderAsset = @import("../../ECSComponents/AComponents.zig").ShaderAsset;
const EngineContext = @import("../../Core/EngineContext.zig");
const PushConstants = @import("../RenderPlatform.zig").PushConstants;
const ComputeOutput = @import("../Renderer.zig").ComputeOutput;
const StorageBufferBinding = @import("../RenderPlatform.zig").StorageBufferBinding;
const PresentMode = @import("../RenderPlatform.zig").PresentMode;
const Tracy = @import("../../Core/Tracy.zig");

const sdl = @import("../../Core/CImports.zig").sdl;

const SDLPlatform = @This();

mDevice: *sdl.SDL_GPUDevice = undefined,
/// The one command buffer a frame records everything into, from its first render to the present, submitted at
/// EndFrame. One submit a frame, and the GPU runs the work in the order it was recorded
mFrameCmdBuffer: ?*sdl.SDL_GPUCommandBuffer = null,
mSwapchainTexture: ?*sdl.SDL_GPUTexture = null,
mSwapchainWidth: usize = 0,
mSwapchainHeight: usize = 0,

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
    //debug mode turns on SDL's own checks and the Vulkan validation layers, when the SDK has them, which cost CPU time
    //on every GPU call: worth it while developing, not in a release build
    _ = sdl.SDL_SetBooleanProperty(props, sdl.SDL_PROP_GPU_DEVICE_CREATE_DEBUGMODE_BOOLEAN, builtin.mode == .debug);
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
    _ = if (self.mFrameCmdBuffer) |cmd| sdl.SDL_CancelGPUCommandBuffer(cmd);
    sdl.SDL_ReleaseWindowFromGPUDevice(self.mDevice, sdl_window);
    sdl.SDL_DestroyGPUDevice(self.mDevice);
}

/// Switches how frames reach the window, between frames only (not while one has its window image). False when it
/// couldn't, and the window keeps the mode it had: not every driver can turn vsync off
pub fn SetPresentMode(self: *SDLPlatform, window: *Window, present_mode: PresentMode) bool {
    std.debug.assert(self.mFrameCmdBuffer == null);
    const sdl_window: *sdl.SDL_Window = @ptrCast(window.GetNativeWindow());
    const sdl_mode: sdl.SDL_GPUPresentMode = switch (present_mode) {
        .VSync => sdl.SDL_GPU_PRESENTMODE_VSYNC,
        .Off => sdl.SDL_GPU_PRESENTMODE_IMMEDIATE,
    };
    if (!sdl.SDL_WindowSupportsGPUPresentMode(self.mDevice, sdl_window, sdl_mode)) return false;
    if (!sdl.SDL_SetGPUSwapchainParameters(self.mDevice, sdl_window, sdl.SDL_GPU_SWAPCHAINCOMPOSITION_SDR, sdl_mode)) {
        std.log.err("SetPresentMode({s}) failed: {s}", .{ @tagName(present_mode), sdl.SDL_GetError() });
        return false;
    }
    return true;
}

pub fn BeginFrame(self: *SDLPlatform, window: *Window) bool {
    std.debug.assert(self.mFrameCmdBuffer == null);
    self.mFrameCmdBuffer = sdl.SDL_AcquireGPUCommandBuffer(self.mDevice);
    std.debug.assert(self.mFrameCmdBuffer != null);

    var swapchain_tex: ?*sdl.SDL_GPUTexture = null;
    var width: usize = 0;
    var height: usize = 0;

    const sdl_window: *sdl.SDL_Window = @ptrCast(window.GetNativeWindow());

    const acquired = sdl.SDL_AcquireGPUSwapchainTexture(
        self.mFrameCmdBuffer,
        sdl_window,
        @ptrCast(&swapchain_tex),
        @ptrCast(&width),
        @ptrCast(&height),
    );

    if (!acquired) {
        _ = sdl.SDL_CancelGPUCommandBuffer(self.mFrameCmdBuffer);
        self.mFrameCmdBuffer = null;
        return false;
    }

    self.mSwapchainTexture = swapchain_tex;
    self.mSwapchainWidth = width;
    self.mSwapchainHeight = height;

    if (self.mSwapchainTexture == null) {
        self.EndFrame();
        return false;
    }

    return true;
}

/// A copy pass in the frame's command buffer: uploads and texture copies go between this and EndCopyPass. Free on
/// Vulkan, but a real pass on other backends, so a render puts all of its copies in one
pub fn BeginCopyPass(self: SDLPlatform) *sdl.SDL_GPUCopyPass {
    const copy_pass = sdl.SDL_BeginGPUCopyPass(self.GetFrameCmdBuff());
    std.debug.assert(copy_pass != null);
    return copy_pass.?;
}

pub fn EndCopyPass(_: SDLPlatform, copy_pass: *anyopaque) void {
    sdl.SDL_EndGPUCopyPass(@ptrCast(@alignCast(copy_pass)));
}

pub fn EndFrame(self: *SDLPlatform) void {
    std.debug.assert(self.mFrameCmdBuffer != null);
    _ = sdl.SDL_SubmitGPUCommandBuffer(self.mFrameCmdBuffer);
    self.mFrameCmdBuffer = null;
}

pub fn Present(self: SDLPlatform, compute_texture: *ComputeOutput) void {
    const sdl_gpu_texture: *sdl.struct_SDL_GPUTexture = @ptrCast(compute_texture.GetTexture());
    const blit_info = sdl.SDL_GPUBlitInfo{
        .source = .{
            .texture = sdl_gpu_texture,
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
            .w = @intCast(self.mSwapchainWidth),
            .h = @intCast(self.mSwapchainHeight),
        },
        .load_op = sdl.SDL_GPU_LOADOP_DONT_CARE,
        .clear_color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
        .flip_mode = sdl.SDL_FLIP_NONE,
        .filter = sdl.SDL_GPU_FILTER_NEAREST,
        .cycle = false,
    };
    sdl.SDL_BlitGPUTexture(self.mFrameCmdBuffer.?, &blit_info);
}

pub fn GetDevice(self: SDLPlatform) *sdl.SDL_GPUDevice {
    return self.mDevice;
}

pub fn GetFrameCmdBuff(self: SDLPlatform) *sdl.SDL_GPUCommandBuffer {
    std.debug.assert(self.mFrameCmdBuffer != null);
    return self.mFrameCmdBuffer.?;
}

pub fn GetSwapchain(self: SDLPlatform) *sdl.SDL_GPUTexture {
    return self.mSwapchainTexture.?;
}

pub fn PushDebugGroup(self: SDLPlatform, message: [:0]const u8) void {
    std.debug.assert(self.mFrameCmdBuffer != null);
    sdl.SDL_PushGPUDebugGroup(self.mFrameCmdBuffer, message.ptr);
}

pub fn PopDebugGroup(self: SDLPlatform) void {
    std.debug.assert(self.mFrameCmdBuffer != null);
    sdl.SDL_PopGPUDebugGroup(self.mFrameCmdBuffer);
}

const std = @import("std");
const sdl = @import("../../Core/CImports.zig").sdl;
const vk = @import("../../Core/CImports.zig").vk;
const MAX_TEXTURES = @import("RenderBindlessReg.zig").MAX_TEXTURES;
const Texture2D = @import("../../Assets/Assets.zig").Texture2D;
const PushConstants = @import("../RenderPlatform.zig").PushConstants;

const VulkanInterop = @This();

pub const empty: VulkanInterop = .{};

mVKInstance: vk.VkInstance = undefined,
mVKPhysicalDevice: vk.PhysicalDevice = undefined,
mVKDevice: vk.VkDevice,

mGetInstanceProcAddr: vk.PFN_vkGetInstanceProcAddr = undefined,
mGetDeviceProcAddr: vk.PFN_vkGetDeviceProcAddr = undefined,
mGetPhysicalDeviceProperties2: vk.PFN_vkGetPhysicalDeviceProperties2 = undefined,
mGetPhysicalDeviceFeatures2: vk.PFN_vkGetPhysicalDeviceFeatures2 = undefined,

mCreateDescriptorSetLayout: vk.PFN_vkCreateDescriptorSetLayout = undefined,
mDestroyDescriptorSetLayout: vk.PFN_vkDestroyDescriptorSetLayout = undefined,
mCreateDescriptorPool: vk.PFN_vkCreateDescriptorPool = undefined,
mDestroyDescriptorPool: vk.PFN_vkDestroyDescriptorPool = undefined,
mAllocateDescriptorSets: vk.PFN_vkAllocateDescriptorSets = undefined,
mUpdateDescriptorSets: vk.PFN_vkUpdateDescriptorSets = undefined,

mCreateSampler: vk.PFN_vkCreateSampler = undefined,
mDestroySampler: vk.PFN_vkDestroySampler = undefined,

mCreateShaderModule: vk.PFN_vkCreateShaderModule = undefined,
mDestroyShaderModule: vk.PFN_vkDestroyShaderModule = undefined,
mCreatePipelineLayout: vk.PFN_vkCreatePipelineLayout = undefined,
mDestroyPipelineLayout: vk.PFN_vkDestroyPipelineLayout = undefined,
mCreateGraphicsPipelines: vk.PFN_vkCreateGraphicsPipelines = undefined,
mDestroyPipeline: vk.PFN_vkDestroyPipeline = undefined,

mCmdBindPipeline: vk.PFN_vkCmdBindPipeline = undefined,
mCmdBindDescriptorSets: vk.PFN_vkCmdBindDescriptorSets = undefined,
mCmdPushConstants: vk.PFN_vkCmdPushConstants = undefined,
mCmdDraw: vk.PFN_vkCmdDraw = undefined,

mCreateImageView: vk.PFN_vkCreateImageView,
mDestroyImageView: vk.PFN_vkDestroyImageView,

pub fn Init(self: *VulkanInterop, sdl_device: *sdl.SDL_GPUDevice) void {
    const raw_get_proc_addr = sdl.SDL_Vulkan_GetVkGetInstanceProcAddr();
    std.debug.assert(raw_get_proc_addr != null);
    self.mGetInstanceProcAddr = @ptrCast(raw_get_proc_addr);

    const props = sdl.SDL_GetGPUDeviceProperties(sdl_device);

    self.mVKInstance = @ptrCast(sdl.SDL_GetPointerProperty(
        props,
        sdl.SDL_PROP_GPU_DEVICE_VULKAN_INSTANCE_POINTER,
        null,
    ) orelse std.debug.panic("Could not get VkInstance from SDL_GPU", .{}));

    self.mVKPhysicalDevice = @ptrCast(sdl.SDL_GetPointerProperty(
        props,
        sdl.SDL_PROP_GPU_DEVICE_VULKAN_PHYSICAL_DEVICE_POINTER,
        null,
    ) orelse std.debug.panic("Could not get VkPhysicalDevice from SDL_GPU", .{}));

    self.mVKDevice = @ptrCast(sdl.SDL_GetPointerProperty(
        props,
        sdl.SDL_PROP_GPU_DEVICE_VULKAN_DEVICE_POINTER,
        null,
    ) orelse std.debug.panic("Could not get VkDevice from SDL_GPU", .{}));

    self.mGetDeviceProcAddr = @ptrCast(self.mGetInstanceProcAddr(self.mVKInstance, "vkGetDeviceProcAddr") orelse std.debug.panic("Could not load vkGetDeviceProcAddr", .{}));

    self.mGetPhysicalDeviceProperties2 = self.LoadInstanceFn(vk.PFN_vkGetPhysicalDeviceProperties2, "vkGetPhysicalDeviceProperties2");
    self.mGetPhysicalDeviceFeatures2 = self.LoadInstanceFn(vk.PFN_vkGetPhysicalDeviceFeatures2, "vkGetPhysicalDeviceFeatures2");

    self.mCreateDescriptorSetLayout = self.LoadDeviceFn(vk.PFN_vkCreateDescriptorSetLayout, "vkCreateDescriptorSetLayout");
    self.mDestroyDescriptorSetLayout = self.LoadDeviceFn(vk.PFN_vkDestroyDescriptorSetLayout, "vkDestroyDescriptorSetLayout");
    self.mCreateDescriptorPool = self.LoadDeviceFn(vk.PFN_vkCreateDescriptorPool, "vkCreateDescriptorPool");
    self.mDestroyDescriptorPool = self.LoadDeviceFn(vk.PFN_vkDestroyDescriptorPool, "vkDestroyDescriptorPool");
    self.mAllocateDescriptorSets = self.LoadDeviceFn(vk.PFN_vkAllocateDescriptorSets, "vkAllocateDescriptorSets");
    self.mUpdateDescriptorSets = self.LoadDeviceFn(vk.PFN_vkUpdateDescriptorSets, "vkUpdateDescriptorSets");
    self.mCreateSampler = self.LoadDeviceFn(vk.PFN_vkCreateSampler, "vkCreateSampler");
    self.mDestroySampler = self.LoadDeviceFn(vk.PFN_vkDestroySampler, "vkDestroySampler");
    self.mCreateShaderModule = self.LoadDeviceFn(vk.PFN_vkCreateShaderModule, "vkCreateShaderModule");
    self.mDestroyShaderModule = self.LoadDeviceFn(vk.PFN_vkDestroyShaderModule, "vkDestroyShaderModule");
    self.mCreatePipelineLayout = self.LoadDeviceFn(vk.PFN_vkCreatePipelineLayout, "vkCreatePipelineLayout");
    self.mDestroyPipelineLayout = self.LoadDeviceFn(vk.PFN_vkDestroyPipelineLayout, "vkDestroyPipelineLayout");
    self.mCreateGraphicsPipelines = self.LoadDeviceFn(vk.PFN_vkCreateGraphicsPipelines, "vkCreateGraphicsPipelines");
    self.mDestroyPipeline = self.LoadDeviceFn(vk.PFN_vkDestroyPipeline, "vkDestroyPipeline");
    self.mCmdBindPipeline = self.LoadDeviceFn(vk.PFN_vkCmdBindPipeline, "vkCmdBindPipeline");
    self.mCmdBindDescriptorSets = self.LoadDeviceFn(vk.PFN_vkCmdBindDescriptorSets, "vkCmdBindDescriptorSets");
    self.mCmdPushConstants = self.LoadDeviceFn(vk.PFN_vkCmdPushConstants, "vkCmdPushConstants");
    self.mCmdDraw = self.LoadDeviceFn(vk.PFN_vkCmdDraw, "vkCmdDraw");

    self.mCreateImageView = self.LoadDeviceFn(vk.PFN_vkCreateImageView, "vkCreateImageView");
    self.mDestroyImageView = self.LoadDeviceFn(vk.PFN_vkDestroyImageView, "vkDestroyImageView");

    self.AssertDescriptorIndexingSupport();

    std.log.info("VulkanInterop: handles and function pointers loaded successfully", .{});
}

pub fn GetRawDevice(self: VulkanInterop) *vk.VkDevice {
    return self.mVKDevice;
}

pub fn CreateDescriptorSetLayout(self: VulkanInterop, layout: *anyopaque, layout_info: *anyopaque) !void {
    const vk_layout: *vk.VkDescriptorSetLayout = @ptrCast(layout);
    const vk_layout_info: *vk.VkDescriptorSetLayoutCreateInfo = @ptrCast(layout_info);

    const result = self.mCreateDescriptorSetLayout(self.mVKDevice, vk_layout_info, null, vk_layout);

    if (result != vk.VK_SUCCESS) return error.VkCreateDescriptorSetLayoutFailed;
}

pub fn CreateDescriptorPool(self: VulkanInterop, pool: *anyopaque, pool_info: *anyopaque) !void {
    const vk_pool: *vk.VkDescriptorPool = @ptrCast(pool);
    const vk_pool_info: *vk.VkDescriptorPoolCreateInfo = @ptrCast(pool_info);

    const result = self.mCreateDescriptorPool(self.mVKDevice, vk_pool_info, null, vk_pool);
    if (result != vk.VK_SUCCESS) return error.VkCreateDescriptorPoolFailed;
}

pub fn AllocateDescriptorSet(self: VulkanInterop, descriptor_set: *anyopaque, alloc_info: *anyopaque) !void {
    const vk_descriptor_set: *vk.VkDescriptorSet = @ptrCast(descriptor_set);
    const vk_alloc_info: *vk.VkDescriptorSetAllocateInfo = @ptrCast(alloc_info);

    const result = self.mAllocateDescriptorSets(self.mVKDevice, vk_alloc_info, vk_descriptor_set);
    if (result != vk.VK_SUCCESS) return error.VkAllocateDescriptorSetsFailed;
}

pub fn CreateSampler(self: VulkanInterop, sampler: *anyopaque, sampler_info: *anyopaque) !void {
    const vk_sampler: *vk.VkSampler = @ptrCast(sampler);
    const vk_sampler_info: *vk.VkSamplerCreateInfo = @ptrCast(sampler_info);

    const result = self.mCreateSampler(self.mVKDevice, &vk_sampler_info, null, vk_sampler);
    if (result != vk.VK_SUCCESS) return error.VkCreateSamplerFailed;
}

pub fn CreateImageView(self: VulkanInterop, image_view: *anyopaque, image_view_info: *anyopaque) !void {
    const vk_image_view: *vk.VkImageView = @ptrCast(image_view);
    const vk_image_view_info: *vk.VkImageViewCreateInfo = @ptrCast(image_view_info);

    const result = self.mCreateImageView(self.mVKDevice, vk_image_view_info, null, &vk_image_view);
    if (result != vk.VK_SUCCESS) return error.VkCreateImageViewFailed;
}

pub fn UpdateDescriptorSets(self: VulkanInterop, writes: *anyopaque, num: usize) !void {
    const vk_writes: *vk.VkWriteDescriptorSet = @ptrCast(writes);

    self.mUpdateDescriptorSets(self.mVKDevice, num, vk_writes, 0, null);
}

pub fn DestroyImageView(self: VulkanInterop, image_view: *anyopaque) void {
    const vk_image_view: *vk.VkImageView = @ptrCast(image_view);
    self.mDestroyImageView(self.mVKDevice, vk_image_view, null);
}

pub fn CreateShaderModule(self: VulkanInterop, module: *anyopaque, module_info: *anyopaque) !void {
    const vk_module: *vk.VkShaderModule = @ptrCast(module);
    const vk_module_info: *vk.VkShaderModuleCreateInfo = @ptrCast(module_info);

    const result = self.mCreateShaderModule(self.mVKDevice, &vk_module_info, null, &vk_module);
    if (result != vk.VK_SUCCESS) return error.VkCreateShaderModuleFailed;
}

pub fn DestroyShaderModule(self: VulkanInterop, module: *anyopaque) void {
    const vk_module: *vk.VkShaderModule = @ptrCast(module);
    self.mDestroyShaderModule(self.mVKDevice, vk_module, null);
}

pub fn CreatePipelineLayout(self: VulkanInterop, layout_info: *anyopaque, pipeline_layout: *anyopaque) !void {
    const vk_layout_info: *vk.VkPipelineLayoutCreateInfo = @ptrCast(layout_info);
    const vk_pipeline_layout: *vk.VkPipelineLayout = @ptrCast(pipeline_layout);

    const result = self.mCreatePipelineLayout(self.mVKDevice, vk_layout_info, null, vk_pipeline_layout);
    if (result != vk.VK_SUCCESS) return error.VkCreatePipelineLayoutFailed;
}

pub fn CreateGraphicsPipelines(self: VulkanInterop, pipeline: *anyopaque, pipeline_info: *anyopaque) !void {
    const vk_pipeline: *vk.VkPipeline = @ptrCast(pipeline);
    const vk_pipeline_info: *vk.VkGraphicsPipelineCreateInfo = @ptrCast(pipeline_info);

    const result = self.mCreateGraphicsPipelines(self.mVKDevice, null, 1, vk_pipeline_info, null, vk_pipeline);
    if (result != vk.VK_SUCCESS) return error.VkCreateGraphicsPipelineFailed;
}

pub fn DestroyPipeline(self: VulkanInterop, pipeline: *anyopaque) void {
    const vk_pipeline: *vk.VkPipeline = @ptrCast(pipeline);
    self.mDestroyPipeline(self.mVKDevice, vk_pipeline, null);
}

pub fn DestroyPipelineLayout(self: VulkanInterop, pipeline_layout: *anyopaque) void {
    const vk_pipeline_layout: *vk.VkPipelineLayout = @ptrCast(pipeline_layout);
    self.mDestroyPipelineLayout(self.mVKDevice, vk_pipeline_layout, null);
}

pub fn DestroyDescriptorSetLayout(self: VulkanInterop, layout: *anyopaque) void {
    const vk_layout: *vk.VkDescriptorSetLayout = @ptrCast(layout);
    self.mDestroyDescriptorSetLayout(self.mVKDevice, vk_layout, null);
}

pub fn CmdBindPipeline(self: VulkanInterop, cmd: *anyopaque, pipeline: *anyopaque) void {
    const vk_cmd: *vk.VkCommandBuffer = @ptrCast(cmd);
    const vk_pipeline: *vk.VkPipeline = @ptrCast(pipeline);

    self.mCmdBindPipeline(vk_cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, vk_pipeline);
}

pub fn CmdBindDescriptorSets(self: VulkanInterop, cmd: *anyopaque, pipeline_layout: *anyopaque, descriptor_sets: *anyopaque, num_descriptor_sets: u32) void {
    const vk_cmd: *vk.VkCommandBuffer = @ptrCast(cmd);
    const vk_pipeline_layout: *vk.VkPipelineLayout = @ptrCast(pipeline_layout);
    const vk_descriptor_sets: *vk.VkDescriptorSetLayout = @ptrCast(descriptor_sets);
    self.mCmdBindDescriptorSets(vk_cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, vk_pipeline_layout, 0, num_descriptor_sets, vk_descriptor_sets, 0, null);
}

pub fn CmdPushConstants(self: VulkanInterop, cmd: *anyopaque, pipeline_layout: *anyopaque, push_constants: *PushConstants) void {
    const vk_cmd: *vk.VkCommandBuffer = @ptrCast(cmd);
    const vk_pipeline_layout: *vk.VkPipelineLayout = @ptrCast(pipeline_layout);
    self.mCmdPushConstants(vk_cmd, vk_pipeline_layout, vk.VK_SHADER_STAGE_FRAGMENT_BIT, 0, @sizeOf(PushConstants), push_constants);
}

pub fn GetRawCommandBuffer(sdl_cmd: *sdl.SDL_GPUCommandBuffer) *vk.VkCommandBuffer {
    const props = sdl.SDL_GetGPUCommandBufferProperties(sdl_cmd);
    return @ptrCast(sdl.SDL_GetPointerProperty(
        props,
        sdl.SDL_PROP_GPU_COMMAND_BUFFER_VULKAN_COMMAND_BUFFER_POINTER,
        null,
    ) orelse std.debug.panic("Could not get VkCommandBuffer from SDL_GPUCommandBuffer", .{}));
}

pub fn GetRawImage(sdl_texture: *sdl.SDL_GPUTexture) *vk.VkImage {
    const props = sdl.SDL_GetGPUTextureProperties(sdl_texture);
    return @ptrCast(sdl.SDL_GetPointerProperty(
        props,
        sdl.SDL_PROP_GPU_TEXTURE_VULKAN_IMAGE_POINTER,
        null,
    ) orelse std.debug.panic("Could not get VkImage from SDL_GPUTexture", .{}));
}

pub fn GetRawBuffer(sdl_buffer: *sdl.SDL_GPUBuffer) *vk.VkBuffer {
    const props = sdl.SDL_GetGPUBufferProperties(sdl_buffer);
    return @ptrCast(sdl.SDL_GetPointerProperty(
        props,
        sdl.SDL_PROP_GPU_BUFFER_VULKAN_BUFFER_POINTER,
        null,
    ) orelse std.debug.panic("Could not get VkBuffer from SDL_GPUBuffer", .{}));
}

pub fn GetMaxSampledImages(self: VulkanInterop) u32 {
    var props = std.mem.zeroes(vk.VkPhysicalDeviceProperties2);
    props.sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2;
    self.mGetPhysicalDeviceProperties2(self.vkPhysicalDevice, &props);
    return props.properties.limits.maxPerStageDescriptorSampledImages;
}

fn LoadInstanceFn(self: VulkanInterop, comptime T: type, name: [*:0]const u8) T {
    return @ptrCast(self.GetInstanceProcAddr(self.vkInstance, name) orelse std.debug.panic("Could not load instance fn: {s}", .{name}));
}

fn LoadDeviceFn(self: VulkanInterop, comptime T: type, name: [*:0]const u8) T {
    return @ptrCast(self.GetDeviceProcAddr(self.vkDevice, name) orelse std.debug.panic("Could not load device fn: {s}", .{name}));
}

fn AssertDescriptorIndexingSupport(self: VulkanInterop) void {
    // Check that VK_EXT_descriptor_indexing features are available.
    // These are core in Vulkan 1.2 and required for bindless textures.
    var indexing_features = std.mem.zeroes(vk.VkPhysicalDeviceDescriptorIndexingFeatures);
    indexing_features.sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_INDEXING_FEATURES;

    var features2 = std.mem.zeroes(vk.VkPhysicalDeviceFeatures2);
    features2.sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
    features2.pNext = &indexing_features;

    self.GetPhysicalDeviceFeatures2(self.vkPhysicalDevice, &features2);

    if (indexing_features.descriptorBindingPartiallyBound != vk.VK_TRUE) {
        std.debug.panic("VulkanInterop: device does not support descriptorBindingPartiallyBound — bindless textures unavailable", .{});
    }
    if (indexing_features.runtimeDescriptorArray != vk.VK_TRUE) {
        std.debug.panic("VulkanInterop: device does not support runtimeDescriptorArray — bindless textures unavailable", .{});
    }
    if (indexing_features.descriptorBindingVariableDescriptorCount != vk.VK_TRUE) {
        std.debug.panic("VulkanInterop: device does not support descriptorBindingVariableDescriptorCount — bindless textures unavailable", .{});
    }
    if (indexing_features.descriptorBindingSampledImageUpdateAfterBind != vk.VK_TRUE) {
        std.debug.panic("VulkanInterop: device does not support descriptorBindingSampledImageUpdateAfterBind — bindless textures unavailable", .{});
    }

    std.log.info("VulkanInterop: descriptor indexing features confirmed", .{});
}

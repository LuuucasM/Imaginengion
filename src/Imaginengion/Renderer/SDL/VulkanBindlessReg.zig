const std = @import("std");
const vk = @import("../../Core/CImports.zig").vk;
const sdl = @import("../../Core/CImports.zig").sdl;
const SkipField = @import("../../Core/SkipField.zig");
const EngineContext = @import("../../Core/EngineContext.zig");
const SDLTexture2D = @import("../../Assets/Assets/Texture2Ds/SDLTexture2D.zig");
const RenderInterop = @import("RenderInterop.zig");
const MAX_TEXTURES = @import("RenderBindlessReg.zig").MAX_TEXTURES;

const BindlessVulkanReg = @This();

const SkipFieldT = SkipField.StaticSkipField(MAX_TEXTURES);

mDescriptorPool: vk.VkDescriptorPool,
mDescriptorSetLayout: vk.VkDescriptorSetLayout,
mDescriptorSet: vk.VkDescriptorSet,
mSampler: vk.VkSampler,

mFreeSkipList: SkipFieldT = .NoSkip,
mImageViews: std.ArrayList(?vk.VkImageView) = .empty,

pub fn Init(self: BindlessVulkanReg, engine_allocator: std.mem.Allocator, interop: *RenderInterop) !void {
    self.mImageViews.ensureTotalCapacity(engine_allocator, MAX_TEXTURES);
    self.mImageViews.expandToCapacity();
    for (0..self.mImageViews.items.len) |i| {
        self.mImageViews.items[i] = null;
    }
    self.mDescriptorSetLayout = try CreateDescriptorSetLayout(interop);
    self.mDescriptorPool = try CreateDescriptorPool(interop);
    self.mDescriptorSet = try self.AllocateDescriptorSet(interop);
    self.mSampler = try CreateSampler(interop);

    std.log.info("BindlessTextureRegistry: initialized ({d} slots)", .{MAX_TEXTURES});
}

pub fn Deinit(self: *BindlessVulkanReg, engine_allocator: std.mem.Allocator) void {
    self.mImageViews.deinit(engine_allocator);
}

pub fn RegisterTexture2D(self: *BindlessVulkanReg, interop: *RenderInterop, texture: *SDLTexture2D, sdl_texture_format: c_int) !u32 {
    const vk_texture_format = ToVKTextureFormat(sdl_texture_format);

    const new_slot = self.mFreeSkipList.mSkipField[0];
    std.debug.assert(new_slot < MAX_TEXTURES);
    std.debug.assert(self.mImageViews.items[new_slot] == null);

    self.mFreeSkipList.ChangeToSkipped(new_slot);
    errdefer self.mFreeSkipList.ChangeToUnskipped(new_slot);

    const vk_image: *vk.VkImage = @ptrCast(RenderInterop.GetRawImage(texture.GetTexture()));

    const view_info = vk.VkImageViewCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .image = vk_image,
        .viewType = vk.VK_IMAGE_VIEW_TYPE_2D,
        .format = vk_texture_format,
        .components = .{
            .r = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
            .g = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
            .b = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
            .a = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
        },
        .subresourceRange = .{
            .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };

    var image_view: vk.VkImageView = undefined;
    try interop.CreateImageView(&image_view, &view_info);

    self.mImageViews[new_slot] = image_view;

    const image_info = vk.VkDescriptorImageInfo{
        .sampler = self.mSampler,
        .imageView = image_view,
        .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
    };

    const write = vk.VkWriteDescriptorSet{
        .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .pNext = null,
        .dstSet = self.mDescriptorSet,
        .dstBinding = 0,
        .dstArrayElement = new_slot,
        .descriptorCount = 1,
        .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .pImageInfo = &image_info,
        .pBufferInfo = null,
        .pTexelBufferView = null,
    };

    interop.UpdateDescriptorSets(&write);

    std.log.debug("BindlessTextureRegistry: registered texture at slot {d}", .{new_slot});
    return new_slot;
}

pub fn Unregister(self: *BindlessVulkanReg, interop: *RenderInterop, slot: u32) void {
    std.debug.assert(slot < MAX_TEXTURES);
    std.debug.assert(self.mImageViews.items[slot] != null);

    interop.DestroyImageView(self.mImageViews[slot]);

    self.mFreeSkipList.ChangeToUnskipped(slot);
    self.mImageViews[slot] = null;

    std.log.debug("BindlessTextureRegistry: unregistered slot {d}", .{slot});
}

pub fn GetDescriptorSet(self: BindlessVulkanReg) *vk.VkDescriptorSet {
    return self.mDescriptorSet;
}

pub fn GetLayout(self: BindlessVulkanReg) *vk.VkDescriptorSetLayout {
    return self.mDescriptorSetLayout;
}

fn CreateDescriptorSetLayout(interop: *RenderInterop) !vk.VkDescriptorSetLayout {
    const binding_flags: vk.VkDescriptorBindingFlags = vk.VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT | vk.VK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT | vk.VK_DESCRIPTOR_BINDING_UPDATE_AFTER_BIND_BIT;

    const flags_info = vk.VkDescriptorSetLayoutBindingFlagsCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO,
        .pNext = null,
        .bindingCount = 1,
        .pBindingFlags = &binding_flags,
    };

    const binding = vk.VkDescriptorSetLayoutBinding{
        .binding = 0,
        .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .descriptorCount = MAX_TEXTURES,
        .stageFlags = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
        .pImmutableSamplers = null,
    };

    const layout_info = vk.VkDescriptorSetLayoutCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .pNext = &flags_info,
        .flags = vk.VK_DESCRIPTOR_SET_LAYOUT_CREATE_UPDATE_AFTER_BIND_POOL_BIT,
        .bindingCount = 1,
        .pBindings = &binding,
    };

    var layout: vk.VkDescriptorSetLayout = undefined;

    try interop.CreateDescriptorSetLayout(&layout, &layout_info);

    return layout;
}

fn CreateDescriptorPool(interop: *RenderInterop) !vk.VkDescriptorPool {
    const pool_size = vk.VkDescriptorPoolSize{
        .type = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .descriptorCount = MAX_TEXTURES,
    };

    const pool_info = vk.VkDescriptorPoolCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .pNext = null,
        .flags = vk.VK_DESCRIPTOR_POOL_CREATE_UPDATE_AFTER_BIND_BIT,
        .maxSets = 1,
        .poolSizeCount = 1,
        .pPoolSizes = &pool_size,
    };

    var pool: vk.VkDescriptorPool = undefined;
    try interop.CreateDescriptorPool(&pool, &pool_info);
    return pool;
}

fn AllocateDescriptorSet(self: BindlessVulkanReg, interop: *RenderInterop) !vk.VkDescriptorSet {
    const variable_count_info = vk.VkDescriptorSetVariableDescriptorCountAllocateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_VARIABLE_DESCRIPTOR_COUNT_ALLOCATE_INFO,
        .pNext = null,
        .descriptorSetCount = 1,
        .pDescriptorCounts = &MAX_TEXTURES,
    };

    const alloc_info = vk.VkDescriptorSetAllocateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .pNext = &variable_count_info,
        .descriptorPool = &self.mDescriptorPool,
        .descriptorSetCount = 1,
        .pSetLayouts = &self.mDescriptorSetLayout,
    };

    var descriptor_set: vk.VkDescriptorSet = undefined;

    try interop.AllocateDescriptorSet(&descriptor_set, &alloc_info);

    return descriptor_set;
}

fn CreateSampler(interop: *RenderInterop) !vk.VkSampler {
    const sampler_info = vk.VkSamplerCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .magFilter = vk.VK_FILTER_LINEAR,
        .minFilter = vk.VK_FILTER_LINEAR,
        .mipmapMode = vk.VK_SAMPLER_MIPMAP_MODE_LINEAR,
        .addressModeU = vk.VK_SAMPLER_ADDRESS_MODE_REPEAT,
        .addressModeV = vk.VK_SAMPLER_ADDRESS_MODE_REPEAT,
        .addressModeW = vk.VK_SAMPLER_ADDRESS_MODE_REPEAT,
        .mipLodBias = 0,
        .anisotropyEnable = vk.VK_FALSE,
        .maxAnisotropy = 1,
        .compareEnable = vk.VK_FALSE,
        .compareOp = vk.VK_COMPARE_OP_NEVER,
        .minLod = 0,
        .maxLod = 0,
        .borderColor = vk.VK_BORDER_COLOR_FLOAT_TRANSPARENT_BLACK,
        .unnormalizedCoordinates = vk.VK_FALSE,
    };
    var sampler: vk.VkSampler = undefined;
    try interop.CreateSampler(&sampler, &sampler_info);
    return sampler;
}

fn ToVKTextureFormat(sdl_texture_format: c_int) c_int {
    return switch (sdl_texture_format) {
        sdl.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM => vk.VK_FORMAT_R8G8B8A8_UNORM,
        else => @panic("texture format currently unsupported!\n"),
    };
}

const std = @import("std");
const vk = @import("../../Core/CImports.zig").vk;
const RenderInterop = @import("RenderInterop.zig");
const RenderBindlessReg = @import("RenderBindlessReg.zig");
const ShaderAsset = @import("../../Assets/Assets.zig").ShaderAsset;
const VulkanPipeline = @This();
const PushConstants = @import("../RenderPlatform.zig").PushConstants;
const PipelineConfig = @import("../RenderPlatform.zig").PipelineConfig;

comptime {
    std.debug.assert(@sizeOf(PushConstants) == 60);
    std.debug.assert(@sizeOf(PushConstants) <= 128);
}

mPipeline: vk.VkPipeline = undefined,
mPipelineLayout: vk.VkPipelineLayout = undefined,
mSSBOSetLayout: vk.VkDescriptorSetLayout = undefined,
mSSBOPool: vk.VkDescriptorPool = undefined,
mSSBOSet: vk.VkDescriptorSet = undefined,

pub fn Init(self: VulkanPipeline, interop: *RenderInterop, registery: *RenderBindlessReg, shader: *ShaderAsset, config: PipelineConfig) !void {
    const vert_module = try CreateShaderModule(interop, shader.mShaderSources.mVertexBinary);
    const frag_module = try CreateShaderModule(interop, shader.mShaderSources.mFragmentBinary);
    defer interop.DestroyShaderModule(vert_module);
    defer interop.DestroyShaderModule(frag_module);

    self.mSSBOSetLayout = try CreateSSBOSetLayout(interop);
    self.mSSBOPool = try CreateSSBOPool(interop);
    self.mSSBOSet = try self.AllocateSSBOSet(interop);

    const vk_reg_layout: ?*vk.VkDescriptorSetLayout = @ptrCast(registery.Getlayout());

    const set_layouts = [_]vk.VkDescriptorSetLayout{
        vk_reg_layout,
        self.mSSBOSetLayout,
    };

    const push_range = vk.VkPushConstantRange{
        .stageFlags = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
        .offset = 0,
        .size = @sizeOf(PushConstants),
    };

    const layout_info = vk.VkPipelineLayoutCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .setLayoutCount = set_layouts.len,
        .pSetLayouts = &set_layouts,
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = &push_range,
    };
    try interop.CreatePipelineLayout(&layout_info, &self.mPipelineLayout);

    self.mPipeline = try self.CreateGraphicsPipeline(interop, vert_module, frag_module, config);
}

pub fn Deinit(self: VulkanPipeline, interop: *RenderInterop) void {
    interop.DestroyPipeline(self.mPipeline);
    interop.DestroyPipelineLayout(self.mPipelineLayout);
    interop.DestroyDescriptorPool(self.mSSBOPool);
    interop.DestroyDescriptorPoolLayout(self.mSSBOSetLayout);
}

pub fn UpdateStorageBuffers(self: VulkanPipeline, interop: *RenderInterop, quad_vk_buff: *vk.VkBuffer, glyph_vk_buff: *vk.VkBuffer) void {
    const quads_buf_info = vk.VkDescriptorBufferInfo{
        .buffer = quad_vk_buff,
        .offset = 0,
        .range = vk.VK_WHOLE_SIZE,
    };
    const glyphs_buf_info = vk.VkDescriptorBufferInfo{
        .buffer = glyph_vk_buff,
        .offset = 0,
        .range = vk.VK_WHOLE_SIZE,
    };
    const writes = [_]vk.VkWriteDescriptorSet{
        .{
            .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .pNext = null,
            .dstSet = self.mSSBOSet,
            .dstBinding = 0,
            .dstArrayElement = 0,
            .descriptorCount = 1,
            .descriptorType = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .pImageInfo = null,
            .pBufferInfo = &quads_buf_info,
            .pTexelBufferView = null,
        },
        .{
            .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .pNext = null,
            .dstSet = self.mSSBOSet,
            .dstBinding = 1,
            .dstArrayElement = 0,
            .descriptorCount = 1,
            .descriptorType = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .pImageInfo = null,
            .pBufferInfo = &glyphs_buf_info,
            .pTexelBufferView = null,
        },
    };
    interop.UpdateDescriptorSets(&writes, 2);
}

pub fn Draw(self: VulkanPipeline, interop: *RenderInterop, cmd: *vk.VkCommandBuffer, registry: *RenderBindlessReg, push_constants: *PushConstants) void {
    interop.CmdBindPipeline(cmd, &self.mPipeline);
    const descriptor_sets = [_]vk.VkDescriptorSet{
        registry.GetDescriptorSet(), // set=0
        self.mSSBOSet, // set=1
    };
    interop.CmdBindDescriptorSets(cmd, self.mPipelineLayout, descriptor_sets, 2);

    interop.CmdPushConstants(cmd, self.mPipelineLayout, push_constants);
}

fn CreateShaderModule(interop: *RenderInterop, spv: []const u8) !vk.VkShaderModule {
    const module_info = vk.VkShaderModuleCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .codeSize = spv.len,
        .pCode = @ptrCast(@alignCast(spv.ptr)),
    };

    var module: vk.VkShaderModule = undefined;
    try interop.CreateShaderModule(&module, &module_info);
    return module;
}

fn CreateSSBOSetLayout(interop: *RenderInterop) !vk.VkDescriptorSetLayout {
    const bindings = [_]vk.VkDescriptorSetLayoutBinding{
        .{
            .binding = 0,
            .descriptorType = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .descriptorCount = 1,
            .stageFlags = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
            .pImmutableSamplers = null,
        },
        .{
            .binding = 1,
            .descriptorType = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .descriptorCount = 1,
            .stageFlags = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
            .pImmutableSamplers = null,
        },
    };
    const layout_info = vk.VkDescriptorSetLayoutCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .bindingCount = bindings.len,
        .pBindings = &bindings,
    };

    var layout: vk.VkDescriptorSetLayout = undefined;

    try interop.CreateDescriptorSetLayout(&layout, &layout_info);

    return layout;
}

fn CreateSSBOPool(interop: *RenderInterop) !vk.VkDescriptorPool {
    const pool_size = vk.VkDescriptorPoolSize{
        .type = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
        .descriptorCount = 2,
    };
    const pool_info = vk.VkDescriptorPoolCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .maxSets = 1,
        .poolSizeCount = 1,
        .pPoolSizes = &pool_size,
    };
    var pool: vk.VkDescriptorPool = undefined;

    try interop.CreateDescriptorPool(&pool, &pool_info);

    return pool;
}

fn AllocateSSBOSet(self: VulkanPipeline, interop: *RenderInterop) !vk.VkDescriptorSet {
    const alloc_info = vk.VkDescriptorSetAllocateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .pNext = null,
        .descriptorPool = &self.mSSBOPool,
        .descriptorSetCount = 1,
        .pSetLayouts = &self.mSSBOSetLayout,
    };

    var descriptor_set: vk.VkDescriptorSet = undefined;

    interop.AllocateDescriptorSet(&descriptor_set, &alloc_info);
}

fn CreateGraphicsPipeline(self: VulkanPipeline, interop: *RenderInterop, vert_module: vk.VkShaderModule, frag_module: vk.VkShaderModule, config: PipelineConfig) !vk.VkPipeline {
    const entry_point: [*:0]const u8 = "main";
    const stages = [_]vk.VkPipelineShaderStageCreateInfo{
        .{
            .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .stage = vk.VK_SHADER_STAGE_VERTEX_BIT,
            .module = vert_module,
            .pName = entry_point,
            .pSpecializationInfo = null,
        },
        .{
            .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .stage = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
            .module = frag_module,
            .pName = entry_point,
            .pSpecializationInfo = null,
        },
    };

    const vertex_input = vk.VkPipelineVertexInputStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .vertexBindingDescriptionCount = 0,
        .pVertexBindingDescriptions = null,
        .vertexAttributeDescriptionCount = 0,
        .pVertexAttributeDescriptions = null,
    };

    const input_assembly = vk.VkPipelineInputAssemblyStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .topology = vk.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        .primitiveRestartEnable = vk.VK_FALSE,
    };

    const viewport_state = vk.VkPipelineViewportStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .viewportCount = 1,
        .pViewports = null,
        .scissorCount = 1,
        .pScissors = null,
    };

    const rasterizer = vk.VkPipelineRasterizationStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .depthClampEnable = vk.VK_FALSE,
        .rasterizerDiscardEnable = vk.VK_FALSE,
        .polygonMode = vk.VK_POLYGON_MODE_FILL,
        .cullMode = vk.VK_CULL_MODE_NONE,
        .frontFace = vk.VK_FRONT_FACE_COUNTER_CLOCKWISE,
        .depthBiasEnable = vk.VK_FALSE,
        .depthBiasConstantFactor = 0,
        .depthBiasClamp = 0,
        .depthBiasSlopeFactor = 0,
        .lineWidth = 1.0,
    };

    const multisampling = vk.VkPipelineMultisampleStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .rasterizationSamples = vk.VK_SAMPLE_COUNT_1_BIT,
        .sampleShadingEnable = vk.VK_FALSE,
        .minSampleShading = 1.0,
        .pSampleMask = null,
        .alphaToCoverageEnable = vk.VK_FALSE,
        .alphaToOneEnable = vk.VK_FALSE,
    };

    const blend_attachment = vk.VkPipelineColorBlendAttachmentState{
        .blendEnable = if (config.enable_blend) vk.VK_TRUE else vk.VK_FALSE,
        .srcColorBlendFactor = vk.VK_BLEND_FACTOR_SRC_ALPHA,
        .dstColorBlendFactor = vk.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        .colorBlendOp = vk.VK_BLEND_OP_ADD,
        .srcAlphaBlendFactor = vk.VK_BLEND_FACTOR_ONE,
        .dstAlphaBlendFactor = vk.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        .alphaBlendOp = vk.VK_BLEND_OP_ADD,
        .colorWriteMask = vk.VK_COLOR_COMPONENT_R_BIT | vk.VK_COLOR_COMPONENT_G_BIT |
            vk.VK_COLOR_COMPONENT_B_BIT | vk.VK_COLOR_COMPONENT_A_BIT,
    };

    const blend_state = vk.VkPipelineColorBlendStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .logicOpEnable = vk.VK_FALSE,
        .logicOp = vk.VK_LOGIC_OP_COPY,
        .attachmentCount = 1,
        .pAttachments = &blend_attachment,
        .blendConstants = .{ 0, 0, 0, 0 },
    };

    const dynamic_states = [_]vk.VkDynamicState{
        vk.VK_DYNAMIC_STATE_VIEWPORT,
        vk.VK_DYNAMIC_STATE_SCISSOR,
    };

    const dynamic_state = vk.VkPipelineDynamicStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .dynamicStateCount = dynamic_states.len,
        .pDynamicStates = &dynamic_states,
    };

    var rendering_info = vk.VkPipelineRenderingCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
        .pNext = null,
        .viewMask = 0,
        .colorAttachmentCount = 1,
        .pColorAttachmentFormats = &config.color_format,
        .depthAttachmentFormat = vk.VK_FORMAT_UNDEFINED,
        .stencilAttachmentFormat = vk.VK_FORMAT_UNDEFINED,
    };

    const pipeline_info = vk.VkGraphicsPipelineCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .pNext = &rendering_info,
        .flags = 0,
        .stageCount = stages.len,
        .pStages = &stages,
        .pVertexInputState = &vertex_input,
        .pInputAssemblyState = &input_assembly,
        .pTessellationState = null,
        .pViewportState = &viewport_state,
        .pRasterizationState = &rasterizer,
        .pMultisampleState = &multisampling,
        .pDepthStencilState = null,
        .pColorBlendState = &blend_state,
        .pDynamicState = &dynamic_state,
        .layout = self.mPipelineLayout,
        .renderPass = null,
        .subpass = 0,
        .basePipelineHandle = null,
        .basePipelineIndex = -1,
    };

    var pipeline: vk.VkPipeline = undefined;
    try interop.CreateGraphicsPipelines(&pipeline, &pipeline_info);
    return pipeline;
}

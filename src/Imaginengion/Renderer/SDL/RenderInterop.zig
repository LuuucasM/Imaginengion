const builtin = @import("builtin");
const sdl = @import("../../Core/CImports.zig").sdl;
const Texture2D = @import("../../Assets/Assets.zig").Texture2D;
const PushConstants = @import("../RenderPlatform.zig").PushConstants;
const RenderInterop = @This();

const Impl = switch (builtin.os.tag) {
    .windows => @import("VulkanInterop.zig"),
    else => @compileError("this shouldnt ever happen!"),
};

_Impl: Impl = .{},

pub fn Init(self: *RenderInterop, sdl_device: *sdl.SDL_GPUDevice) void {
    self._Impl.Init(sdl_device);
}

pub fn GetRawDevice(self: RenderInterop) *anyopaque {
    return self._Impl.GetRawDevice();
}

pub fn CreateDescriptorSetLayout(self: RenderInterop, layout: *anyopaque, layout_info: *anyopaque) !void {
    try self._Impl.CreateDescriptorSetLayout(layout, layout_info);
}

pub fn CreateDescriptorPool(self: RenderInterop, pool: *anyopaque, pool_info: *anyopaque) !void {
    try self._Impl.CreateDescriptorPool(pool, pool_info);
}

pub fn AllocateDescriptorSet(self: RenderInterop, descriptor_set: *anyopaque, alloc_info: *anyopaque) !void {
    try self._Impl.AllocateDescriptorSet(descriptor_set, alloc_info);
}

pub fn CreateSampler(self: RenderInterop, sampler: *anyopaque, sampler_info: *anyopaque) !void {
    try self._Impl.CreateSampler(sampler, sampler_info);
}

pub fn CreateImageView(self: RenderInterop, image_view: *anyopaque, image_view_info: *anyopaque) !void {
    try self._Impl.CreateImageView(image_view, image_view_info);
}

pub fn UpdateDescriptorSets(self: RenderInterop, write: *anyopaque, num: usize) !void {
    try self._Impl.UpdateDescriptorSets(write, num);
}

pub fn DestroyImageView(self: RenderInterop, image_view: *anyopaque) void {
    self._Impl.DestroyImageView(image_view);
}

pub fn CreateShaderModule(self: RenderInterop, module: *anyopaque, module_info: *anyopaque) !void {
    try self._Impl.CreateShaderModule(module, module_info);
}

pub fn DestroyShaderModule(self: RenderInterop, module: *anyopaque) void {
    self._Impl.DestroyShaderModule(module);
}

pub fn CreatePipelineLayout(self: RenderInterop, layout_info: *anyopaque, pipeline_layout: *anyopaque) !void {
    try self._Impl.CreatePipelineLayout(layout_info, pipeline_layout);
}

pub fn CreateGraphicsPipelines(self: RenderInterop, pipeline: *anyopaque, pipeline_info: *anyopaque) !void {
    try self._Impl.CreateGraphicsPipelines(pipeline, pipeline_info);
}

pub fn DestroyPipeline(self: RenderInterop, pipeline: *anyopaque) void {
    self._Impl.DestroyPipeline(pipeline);
}

pub fn DestroyPipelineLayout(self: RenderInterop, pipeline_layout: *anyopaque) void {
    self._Impl.DestroyPipelineLayout(pipeline_layout);
}

pub fn DestroyDescriptorSetLayout(self: RenderInterop, layout: *anyopaque) void {
    self._Impl.DestroyDescriptorSetLayout(layout);
}

pub fn CmdBindPipeline(self: RenderInterop, cmd: *anyopaque, pipeline: *anyopaque) void {
    self._Impl.CmdBindPipeline(cmd, pipeline);
}

pub fn CmdBindDescriptorSets(self: RenderInterop, cmd: *anyopaque, pipeline_layout: *anyopaque, descriptor_sets: *anyopaque, num_descriptor_sets: u32) void {
    self._Impl.CmdBindDescriptorSets(cmd, pipeline_layout, descriptor_sets, num_descriptor_sets);
}

pub fn CmdPushConstants(self: RenderInterop, cmd: *anyopaque, pipeline_layout: *anyopaque, push_constants: *PushConstants) void {
    self._Impl.CmdPushConstants(cmd, pipeline_layout, push_constants);
}

pub fn GetRawCommandBuffer(sdl_cmd: *sdl.SDL_GPUCommandBuffer) *anyopaque {
    return Impl.GetRawCommandBuffer(sdl_cmd);
}

pub fn GetRawImage(sdl_texture: *sdl.SDL_GPUTexture) *anyopaque {
    return Impl.GetRawImage(sdl_texture);
}

pub fn GetRawBuffer(sdl_buffer: *sdl.SDL_GPUBuffer) *anyopaque {
    return Impl.GetRawBuffer(sdl_buffer);
}

pub fn GetMaxSampledImages(self: RenderInterop) u32 {
    return self._Impl.GetMaxSampledImages();
}

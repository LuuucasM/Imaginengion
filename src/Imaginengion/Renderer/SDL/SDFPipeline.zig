const std = @import("std");
const builtin = @import("builtin");
const sdl = @import("../../Core/CImports.zig").sdl;
const RenderInterop = @import("RenderInterop.zig");
const RenderBindlessReg = @import("RenderBindlessReg.zig");
const ShaderAsset = @import("../../Assets/Assets.zig").ShaderAsset;
const PipelineConfig = @import("../RenderPlatform.zig").PipelineConfig;
const PushConstants = @import("../RenderPlatform.zig").PushConstants;
const StorageBufferBinding = @import("../RenderPlatform.zig").StorageBufferBinding;

const Impl = switch (builtin.os.tag) {
    .windows => @import("VulkanPipeline.zig"),
    else => @compileError("not suported currently!\n"),
};

const RenderPipeline = @This();

_Impl: Impl = .{},

pub fn Init(self: RenderPipeline, interop: *RenderInterop, registery: *RenderBindlessReg, shader: *ShaderAsset, config: PipelineConfig) !void {
    self._Impl.Init(interop, registery, shader, config);
}

pub fn Deinit(self: RenderPipeline, interop: *RenderInterop) void {
    self._Impl.Deinit(interop);
}

pub fn UpdateStorageBuffers(self: RenderPipeline, interop: *RenderInterop, buffers: []StorageBufferBinding) void {
    self._Impl.UpdateStorageBuffers(interop, buffers);
}

pub fn Draw(self: RenderPipeline, interop: *RenderInterop, cmd: *sdl.SDL_GPUCommandBuffer, bindless_reg: *RenderBindlessReg, push_constants: *PushConstants) void {
    self._Impl.Draw(interop, interop.GetRawCommandBuffer(cmd), bindless_reg, push_constants);
}

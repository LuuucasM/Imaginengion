const std = @import("std");
const VertexArray = @import("../VertexArrays/VertexArray.zig");
const Window = @import("../Windows/Window.zig");
const builtin = @import("builtin");
const Tracy = @import("../Core/Tracy.zig");
const Texture2D = @import("../Assets/Assets.zig").Texture2D;
const ShaderAsset = @import("../Assets/Assets.zig").ShaderAsset;
const EngineContext = @import("../Core/EngineContext.zig");
const ComputeOutput = @import("Renderer.zig").ComputeOutput;
const PushConstants = @import("RenderPipeline.zig");

pub const StorageBufferBinding = struct {
    buffer: *anyopaque,
    binding: u32, // matches set=1, binding=N in the shader
};

const Impl = switch (builtin.os.tag) {
    .windows => @import("backends/SDLPlatform.zig"),
    else => @import("UnsupportedContext.zig"),
};

const Platform = @This();

_Impl: Impl = .{},

pub fn Init(self: *Platform, engine_context: *EngineContext) void {
    self._Impl.Init(engine_context);
}
pub fn Deinit(self: *Platform, window: *Window) void {
    self._Impl.Deinit(window);
}

pub fn BeginFrame(self: *Platform, window: *Window) bool {
    return self._Impl.BeginFrame(window);
}

pub fn StartCmdBuff(self: *Platform) void {
    self._Impl.StartCmdBuff();
}

pub fn EndCmdBuff(self: *Platform) void {
    self._Impl.EndCmdBuff();
}

pub fn EndFrame(self: *Platform) void {
    self._Impl.EndFrame();
}

pub fn GetMaxTextureImageSlots(self: Platform) usize {
    return self._Impl.GetMaxTextureImageSlots();
}

pub fn GetDevice(self: Platform) *anyopaque {
    return self._Impl.GetDevice();
}

pub fn Present(self: Platform, compute_texture: *ComputeOutput) void {
    self._Impl.Present(compute_texture);
}

pub fn GetFrameCmdBuff(self: Platform) *anyopaque {
    return self._Impl.GetFrameCmdBuff();
}

pub fn GetWorkCmdBuff(self: Platform) *anyopaque {
    return self._Impl.GetWorkCmdBuff();
}

pub fn GetSwapchain(self: Platform) *anyopaque {
    return self._Impl.GetSwapchain();
}

pub fn PushDebugGroup(self: Platform, message: [:0]const u8) void {
    self._Impl.PushDebugGroup(message);
}

pub fn PopDebugGroup(self: Platform) void {
    self._Impl.PopDebugGroup();
}

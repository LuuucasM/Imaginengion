const std = @import("std");
const VertexArray = @import("../VertexArrays/VertexArray.zig");
const Window = @import("../Windows/Window.zig");
const builtin = @import("builtin");
const Vec4f32 = @import("../Math/LinAlg.zig").Vec4f32;
const Tracy = @import("../Core/Tracy.zig");
const Texture2D = @import("../Assets/Assets.zig").Texture2D;
const ShaderAsset = @import("../Assets/Assets.zig").ShaderAsset;
const EngineContext = @import("../Core/EngineContext.zig");

pub const PushConstants = extern struct {
    rotation: [4]f32, // 16 bytes
    position: [3]f32, // 12 bytes
    perspective_far: f32, //  4 bytes  → 32
    resolution_width: f32, //  4 bytes
    resolution_height: f32, //  4 bytes
    aspect_ratio: f32, //  4 bytes
    fov: f32, //  4 bytes  → 48
    mode: u32, //  4 bytes  → 52
    quads_count: u32, //  4 bytes  → 56
    glyphs_count: u32, //  4 bytes  → 60
};

pub const StorageBufferBinding = struct {
    buffer: *anyopaque,
    binding: u32, // matches set=1, binding=N in the shader
};

pub const PipelineConfig = struct {
    color_format: c_uint,
    enable_blend: bool = true,
};

const Impl = switch (builtin.os.tag) {
    .windows => @import("SDL/SDLPlatform.zig"),
    else => @import("UnsupportedContext.zig"),
};

const Platform = @This();

_Impl: Impl = .{},

pub fn Init(self: *Platform, engine_context: *EngineContext, shader: *ShaderAsset) void {
    self._Impl.Init(engine_context, shader);
}
pub fn Deinit(self: *Platform, window: *Window) void {
    self._Impl.Deinit(window);
}

pub fn BeginFrame(self: *Platform, window: *Window) bool {
    return self._Impl.BeginFrame(window);
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

pub fn GetCommandBuff(self: Platform) *anyopaque {
    return self._Impl.GetCommandBuff();
}

pub fn RegisterTexture2D(self: Platform, texture_2d: *anyopaque, texture_format: u32) u32 {
    return self._Impl.RegisterTexture2D(texture_2d, texture_format);
}

pub fn UpdateStorageBuffers(self: Platform, buffers: []StorageBufferBinding) void {
    self._Impl.UpdateStorageBuffers(buffers);
}

pub fn Unregister(self: *Platform, slot: u32) void {
    self._Impl.Unregister(slot);
}

pub fn Draw(self: Platform, cmd: *anyopaque, push_constants: PushConstants) void {
    self._Impl.Draw(cmd, push_constants);
}

pub fn PushDebugGroup(self: Platform, message: []const u8) void {
    self._Impl.PushDebugGroup(message);
}

pub fn PopDebugGroup(self: Platform) void {
    self._Impl.PopDebugGroup();
}

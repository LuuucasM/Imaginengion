const builtin = @import("builtin");
const EngineContext = @import("../Core/EngineContext.zig");

const TextureManager = @This();

const Impl = switch (builtin.os.tag) {
    .windows => @import("backends/SGTextureManager.zig"),
    else => @compileError("Not supported platform"),
};

_Impl: Impl = .{},

pub fn Init(self: *TextureManager, engine_context: *EngineContext, vram_bytes_size: usize) !void {
    try self._Impl.Init(engine_context, vram_bytes_size);
}

pub fn Deinit(self: *TextureManager, engine_context: *EngineContext) void {
    self._Impl.Deinit(engine_context);
}

pub fn Bind(self: TextureManager, render_pass: *anyopaque) void {
    self._Impl.Bind(render_pass);
}

pub fn Register(self: *TextureManager, engine_context: *EngineContext, pixels: *anyopaque, width: usize, height: usize) !u32 {
    try self._Impl.Register(engine_context, pixels, width, height);
}

pub fn Unregister(self: *TextureManager, texture_location: u32) void {
    self._Impl.Unregister(texture_location);
}

pub fn GetNormalizedOffsets(self: *TextureManager, texture_handle: u32) struct { f32, f32 } {
    return self._Impl.GetNormalizedOffsets(texture_handle);
}

pub fn GetPixelOffsets(self: *TextureManager, texture_handle: u32) struct { usize, usize } {
    return self._Impl.GetPixelOffsets(texture_handle);
}

pub fn GetTexture(self: TextureManager) *anyopaque {
    return self._Impl.GetTexture();
}
pub fn GetSampler(self: TextureManager) *anyopaque {
    return self._Impl.GetSampler();
}

pub fn GetSlotIndex(_: TextureManager, texture_handle: u32) usize {
    return Impl.GetSlotIndex(texture_handle);
}

pub fn GetLayerIndex(_: TextureManager, texture_handle: u32) usize {
    return Impl.GetLayerIndex(texture_handle);
}

pub fn GetBinIndex(_: TextureManager, texture_handle: u32) usize {
    return Impl.GetBinIndex(texture_handle);
}

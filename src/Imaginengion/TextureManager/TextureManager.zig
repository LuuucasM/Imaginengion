const builtin = @import("builtin");
const EngineContext = @import("../Core/EngineContext.zig");
const GPUAllocator = @import("../Core/GPUAllocator.zig");
const AtlasHandle = @import("AtlasHandle.zig");
const MathTypes = @import("../Math/MathTypes.zig");
const Vec2 = MathTypes.Vec2;
const Vec3 = MathTypes.Vec3;

const TextureManager = @This();

const Impl = switch (builtin.os.tag) {
    .windows, .vulkan => @import("backends/SGTextureManager.zig"),
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

pub fn BindCompute(self: TextureManager, render_pass: *anyopaque) void {
    self._Impl.BindCompute(render_pass);
}

pub const Usage = Impl.Usage;

/// How many bytes the atlas slot `texture_handle` takes, padding included
pub fn SlotBytes(texture_handle: u32) u64 {
    const slot_size: u64 = AtlasHandle.SlotSize(AtlasHandle.Class(texture_handle));
    return slot_size * slot_size * 4;
}

/// How much of the atlas is in use, by size of texture
pub fn GetUsage(self: *TextureManager) Usage {
    return self._Impl.GetUsage();
}

/// A slot for a texture, counted for `owner` (GPUAllocator.AtlasTook)
pub fn Register(self: *TextureManager, engine_context: *EngineContext, pixels: ?*anyopaque, width: usize, height: usize, owner: GPUAllocator.Owner) !u32 {
    return try self._Impl.Register(engine_context, pixels, width, height, owner);
}

/// Copies a GPU texture's pixels into a registered slot, on the GPU, in a copy pass (see the backend's CopyFromTexture)
pub fn CopyFromTexture(self: *TextureManager, copy_pass: *anyopaque, source: *anyopaque, texture_location: u32, width: usize, height: usize) void {
    self._Impl.CopyFromTexture(copy_pass, source, texture_location, width, height);
}

pub fn Unregister(self: *TextureManager, engine_context: *EngineContext, texture_location: u32) void {
    self._Impl.Unregister(engine_context, texture_location);
}

/// Once a frame, after it is submitted: lets go of what the atlas replaced while it was recorded, and shrinks it if it
/// has free layers to give back
pub fn OnFrameEnd(self: *TextureManager, engine_context: *EngineContext) !void {
    try self._Impl.OnFrameEnd(engine_context);
}

pub fn GetTexture(self: TextureManager) *anyopaque {
    return self._Impl.GetTexture();
}
pub fn GetSampler(self: TextureManager) *anyopaque {
    return self._Impl.GetSampler();
}

pub fn GetLayerIndex(texture_handle: u32) usize {
    return Impl.GetLayerIndex(texture_handle);
}

pub fn GetTextureUV(texture_handle: u32, local_uv: Vec2(f32), tex_width: u32, tex_height: u32) Vec3(f32) {
    return Impl.GetTextureUV(texture_handle, local_uv, tex_width, tex_height);
}

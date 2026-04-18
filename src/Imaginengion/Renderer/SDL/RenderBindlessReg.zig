const std = @import("std");
const builtin = @import("builtin");
const RenderInterop = @import("RenderInterop.zig");
const SDLTexture2D = @import("../../Assets/Assets/Texture2Ds/SDLTexture2D.zig");

pub const MAX_TEXTURES: u32 = 4096;
const BindlessReg = @This();

const Impl = switch (builtin.os.tag) {
    .windows => @import("VulkanBindlessReg.zig"),
    else => @compileError("This isnt implemented yet"),
};

_Impl: Impl = .{},

pub fn Init(self: BindlessReg, engine_allocator: std.mem.Allocator, interop: *RenderInterop) !void {
    try self._Impl.Init(engine_allocator, interop);
}

pub fn Deinit(self: *BindlessReg, engine_allocator: std.mem.Allocator) void {
    self._Impl.Deinit(engine_allocator);
}

pub fn RegisterTexture2D(self: *BindlessReg, interop: *RenderInterop, texture: *SDLTexture2D, sdl_texture_format: c_int) !u32 {
    try self._Impl.RegisterTexture2D(interop, texture, sdl_texture_format);
}

pub fn Unregister(self: *BindlessReg, interop: *RenderInterop, slot: u32) void {
    self._Impl.Unregister(interop, slot);
}

pub fn GetDescriptorSet(self: BindlessReg) *anyopaque {
    return self._Impl.GetDescriptorSet();
}

pub fn GetLayout(self: BindlessReg) *anyopaque {
    return self._Impl.GetLayout();
}

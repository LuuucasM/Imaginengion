const std = @import("std");
const builtin = @import("builtin");
const Vec4f32 = @import("../Math/LinAlg.zig").Vec4f32;

const Impl = switch (builtin.os.tag) {
    .windows => @import("OpenGLFrameBuffer.zig").OpenGLFrameBuffer,
    else => @import("UnsupportedFrameBuffer.zig").UnsupportedFrameBuffer,
};

pub const TextureFormat = enum(u4) {
    None = 0,
    RGBA8 = 1,
    RGBA16F = 2,
    RGBA32F = 3,
    RG32F = 4,
    RED_INTEGER = 5,
    DEPTH32F = 6,
    DEPTH24STENCIL8 = 7,
};

pub fn FrameBuffer(color_texture_formats: []const TextureFormat, depth_texture_format: TextureFormat, samples: u32, is_swap_chain_target: bool) type {
    return struct {
        const Self = @This();
        mImpl: Impl(color_texture_formats, depth_texture_format, samples, is_swap_chain_target),

        pub fn Init(width: usize, height: usize) Self {
            return Self{
                .mImpl = Impl(color_texture_formats, depth_texture_format, samples, is_swap_chain_target).Init(width, height),
            };
        }
        pub fn Deinit(self: Self) void {
            self.mImpl.Deinit();
        }
        pub fn Invalidate(self: *Self) void {
            self.mImpl.Invalidate();
        }
        pub fn Bind(self: Self) void {
            self.mImpl.Bind();
        }
        pub fn Unbind(self: Self) void {
            self.mImpl.Unbind();
        }
        pub fn Resize(self: *Self, width: usize, height: usize) void {
            self.mImpl.Resize(width, height);
        }
        pub fn GetColorAttachmentID(self: Self, attachment_index: u8) u32 {
            return self.mImpl.GetColorAttachmentID(attachment_index);
        }
        pub fn ClearFrameBuffer(self: Self, color: Vec4f32) void {
            self.mImpl.ClearFrameBuffer(color);
        }
        pub fn ClearColorAttachment(self: Self, attachment_index: u8, value: u32) void {
            self.mImpl.ClearColorAttachment(attachment_index, value);
        }
        pub fn BindColorAttachment(self: Self, attachment_index: u8, slot: usize) void {
            self.mImpl.BindColorAttachment(attachment_index, slot);
        }
        pub fn BindDepthAttachment(self: Self, slot: usize) void {
            self.mImpl.BindDepthAttachment(slot);
        }
    };
}

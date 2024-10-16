const std = @import("std");
const builtin = @import("builtin");
const Impl = switch (builtin.os.tag) {
    .windows => @import("OpenGLFrameBuffer.zig").OpenGLFrameBuffer,
    else => @import("UnsupportedFrameBuffer.zig").UnsupportedFrameBuffer,
};

pub const TextureFormat = enum {
    None,
    RGBA8,
    RGBA16F,
    RGBA32F,
    RG32F,
    RED_INTEGER,
    DEPTH32F,
    DEPTH24STENCIL8,
};

pub fn FrameBuffer(color_texture_formats: []TextureFormat, depth_texutre_format: TextureFormat, samples: u32, is_swap_chain_target: bool) type {
    return struct{
        const FrameBuffer = @This();
        mImpl: Impl(color_texture_formats, depth_texture_format, samples, is_swap_chain_target),

        pub fn Init(width: usize, height: usize) FrameBuffer {
            return FrameBuffer{
                .mImpl = Impl(color_texture_formats, depth_texture_format, samples, is_swap_chain_target).Init(width, height),
            };
        }
        pub fn Deinit(self: FrameBuffer) void {
            self.mImpl.Deinit();
        }
        pub fn Invalidate(self: FrameBuffer) void {
            self.mImpl.Invalidate();
        }
        pub fn Bind(self: FrameBuffer) void {
            self.mImpl.Bind();
        }
        pub fn Unbind(self: FrameBuffer) void {
            self.mImpl.Unbind();
        }
        pub fn Resize(self: FrameBuffer, width: usize, height: usize) void {
            self.mImpl.Resize(width, height);
        }
        pub fn ClearColorAttachment(self: FrameBuffer, attachment_index: u8, value: u32) void {
            self.mImpl.ClearColorAttachment(attachment_index, value);
        }

        //For clicking on the viewport in the editor
        pub fn ReadPixel(self: FrameBuffer, attachment_index: u8, x: u32, y: u32) u32 {
            self.mImpl.ReadPixel(attachment_index, x, y);
        }
    };
}
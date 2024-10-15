const std = @import("std");
const builtin = @import("builtin");

const Impl = switch (builtin.os.tag) {
    .windows => @import("OpenGLFrameBuffer.zig"),
    else => @import("UnsupportedFrameBuffer.zig"),
};

pub const FrameBufferTextureFormat = enum {
    RGBA8,
    RGBA16F,
    RGBA32F,
    RG32F,
    RED_INTEGER,
    DEPTH32F,
    DEPTH24STENCIL8,
};

pub const FrameBufferConfig = struct {
    Width: usize,
    Height: usize,
    Attachments: [6]FrameBufferTextureFormat,
    NumOfAttachments: u8,
    Samples: u32,
    IsSwapChainTarget: bool,
};

mColorAttachmentSpecs: [6]FrameBufferTextureFormat,
mNumOfAttachments: u8,
mDepthAttachmentSpec: FrameBufferTextureFormat,
mFrameBufferConfig: FrameBufferConfig,
mBufferID: u32,

mColorAttachments: [6]u8,
mDepthAttachments: u8,

pub fn Init() void {}
pub fn Deinit() void {}
pub fn Invalidate() void {}
pub fn Bind() void {}
pub fn Unbind() void {}
pub fn Resize() void {}

//For clicking on the viewport in the editor
pub fn ReadPixel() void {}

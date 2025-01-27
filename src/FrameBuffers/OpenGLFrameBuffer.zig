const std = @import("std");
const TextureFormat = @import("InternalFrameBuffer.zig").TextureFormat;
const glad = @import("../Core/CImports.zig").glad;

pub fn OpenGLFrameBuffer(comptime color_texture_formats: []const TextureFormat, comptime depth_texture_format: TextureFormat, comptime samples: u32, comptime is_swap_chain_target: bool) type {
    _ = is_swap_chain_target;
    comptime std.debug.assert(color_texture_formats.len <= 5);
    return struct {
        const Self = @This();

        mBufferID: c_uint,
        mColorAttachments: [color_texture_formats.len]u32,
        mDepthAttachment: u32,
        mWidth: usize,
        mHeight: usize,

        pub fn Init(width: usize, height: usize) Self {
            var new_framebuffer = Self{
                .mBufferID = 0,
                .mColorAttachments = std.mem.zeroes([color_texture_formats.len]u32),
                .mDepthAttachment = 0,
                .mWidth = width,
                .mHeight = height,
            };

            new_framebuffer.Create();
            return new_framebuffer;
        }
        pub fn Deinit(self: Self) void {
            glad.glDeleteFramebuffers(1, &self.mBufferID);
            glad.glDeleteTextures(self.mColorAttachments.len, &self.mColorAttachments[0]);
            glad.glDeleteTextures(1, &self.mDepthAttachment);
        }
        pub fn Invalidate(self: *Self) void {
            glad.glDeleteFramebuffers(1, &self.mBufferID);
            glad.glDeleteTextures(self.mColorAttachments.len, &self.mColorAttachments[0]);
            glad.glDeleteTextures(1, &self.mDepthAttachment);

            self.Create();
        }
        pub fn Bind(self: Self) void {
            glad.glBindFramebuffer(glad.GL_FRAMEBUFFER, self.mBufferID);
            glad.glViewport(0.0, 0.0, @intCast(self.mWidth), @intCast(self.mHeight));
        }
        pub fn Unbind(self: Self) void {
            _ = self;
            glad.glBindFramebuffer(glad.GL_FRAMEBUFFER, 0);
        }
        pub fn Resize(self: *Self, width: usize, height: usize) void {
            if (width < 1 or height < 1 or width > 8192 or height > 8192) {
                std.log.warn("attachment index must be within bounds!\n", .{});
                return;
            }
            self.mWidth = width;
            self.mHeight = height;
            self.Invalidate();
        }
        pub fn ClearColorAttachment(self: Self, attachment_index: u32, value: u32) void {
            std.debug.assert(attachment_index < color_texture_formats.len);

            glad.glClearTexImage(self.mColorAttachments[attachment_index], 0, TextureFormatToInternalFormat(color_texture_formats[attachment_index]), glad.GL_UNSIGNED_INT, &value);
        }

        pub fn BindColorAttachment(self: Self, attachment_index: u8, slot: usize) void {
            glad.glBindTextureUnit(@intCast(slot), self.mColorAttachments[attachment_index]);
        }

        pub fn BindDepthAttachment(self: Self, slot: usize) void {
            glad.glBindTextureUnit(@intCast(slot), self.mDepthAttachment);
        }

        fn Create(self: *Self) void {
            glad.glCreateFramebuffers(1, &self.mBufferID);
            glad.glBindFramebuffer(glad.GL_FRAMEBUFFER, self.mBufferID);

            const multisampled: bool = samples > 1;

            //color attachments
            if (self.mColorAttachments.len > 0) {
                glad.glCreateTextures(TextureTarget(multisampled), self.mColorAttachments.len, &self.mColorAttachments[0]);
                for (color_texture_formats, 0..) |texture_format, i| {
                    glad.glBindTexture(TextureTarget(multisampled), self.mColorAttachments[i]);
                    AttachColorTexture(self.mColorAttachments[i], TextureFormatToInternalFormat(texture_format), TextureFormatToFormat(texture_format), @intCast(self.mWidth), @intCast(self.mHeight), @intCast(i), multisampled);
                }
            }

            //depths attachments
            if (depth_texture_format != TextureFormat.None) {
                glad.glCreateTextures(TextureTarget(multisampled), 1, &self.mDepthAttachment);
                glad.glBindTexture(TextureTarget(multisampled), self.mDepthAttachment);
                AttachDepthTexture(self.mDepthAttachment, TextureFormatToInternalFormat(depth_texture_format), @intCast(self.mWidth), @intCast(self.mHeight), multisampled);
            }

            if (self.mColorAttachments.len > 1) {
                const buffers: [5]glad.GLenum = .{ glad.GL_COLOR_ATTACHMENT0, glad.GL_COLOR_ATTACHMENT1, glad.GL_COLOR_ATTACHMENT2, glad.GL_COLOR_ATTACHMENT3, glad.GL_COLOR_ATTACHMENT4 };
                glad.glDrawBuffers(@intCast(buffers.len), &buffers[0]);
            } else if (self.mColorAttachments.len == 0) {
                glad.glDrawBuffer(glad.GL_NONE);
            }

            std.debug.assert(glad.glCheckFramebufferStatus(glad.GL_FRAMEBUFFER) == glad.GL_FRAMEBUFFER_COMPLETE);

            glad.glBindFramebuffer(glad.GL_FRAMEBUFFER, 0);
        }

        fn TextureTarget(multisample: bool) glad.GLenum {
            return if (multisample == true) glad.GL_TEXTURE_2D_MULTISAMPLE else glad.GL_TEXTURE_2D;
        }

        fn AttachColorTexture(attachment_id: u32, internal_format: glad.GLenum, format: glad.GLenum, width: usize, height: usize, index: c_uint, multisampled: bool) void {
            if (multisampled == true) {
                glad.glTexImage2DMultisample(glad.GL_TEXTURE_2D_MULTISAMPLE, samples, internal_format, @intCast(width), @intCast(height), glad.GL_FALSE);
            } else {
                glad.glTexImage2D(glad.GL_TEXTURE_2D, 0, @intCast(internal_format), @intCast(width), @intCast(height), 0, format, glad.GL_UNSIGNED_BYTE, null);

                glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_MIN_FILTER, glad.GL_LINEAR);
                glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_MAG_FILTER, glad.GL_LINEAR);
                glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_WRAP_R, glad.GL_CLAMP_TO_EDGE);
                glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_WRAP_S, glad.GL_CLAMP_TO_EDGE);
                glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_WRAP_T, glad.GL_CLAMP_TO_EDGE);
            }

            glad.glFramebufferTexture2D(glad.GL_FRAMEBUFFER, @as(c_uint, @intCast(glad.GL_COLOR_ATTACHMENT0)) + index, TextureTarget(multisampled), attachment_id, 0);
        }

        fn AttachDepthTexture(attachment_id: u32, internal_format: glad.GLenum, width: usize, height: usize, multisampled: bool) void {
            if (multisampled == true) {
                glad.glTexImage2DMultisample(glad.GL_TEXTURE_2D_MULTISAMPLE, samples, internal_format, @intCast(width), @intCast(height), glad.GL_FALSE);
            } else {
                glad.glTexStorage2D(glad.GL_TEXTURE_2D, 1, internal_format, @intCast(width), @intCast(height));

                glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_MIN_FILTER, glad.GL_LINEAR);
                glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_MAG_FILTER, glad.GL_LINEAR);
                glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_WRAP_R, glad.GL_CLAMP_TO_EDGE);
                glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_WRAP_S, glad.GL_CLAMP_TO_EDGE);
                glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_WRAP_T, glad.GL_CLAMP_TO_EDGE);
            }

            glad.glFramebufferTexture2D(glad.GL_FRAMEBUFFER, glad.GL_DEPTH_STENCIL_ATTACHMENT, TextureTarget(multisampled), attachment_id, 0);
        }

        fn TextureFormatToInternalFormat(format: TextureFormat) glad.GLenum {
            return switch (format) {
                .RGBA8 => glad.GL_RGBA8,
                .RED_INTEGER => glad.GL_R32UI,
                .DEPTH24STENCIL8 => glad.GL_DEPTH24_STENCIL8,
                else => @panic("This texture format isnt implemented yet!"),
            };
        }
        fn TextureFormatToFormat(format: TextureFormat) glad.GLenum {
            return switch (format) {
                .RGBA8 => glad.GL_RGBA,
                .RED_INTEGER => glad.GL_RED_INTEGER,
                .DEPTH24STENCIL8 => glad.GL_DEPTH_STENCIL,
                else => @panic("This texture format isnt implemented yet!"),
            };
        }
    };
}

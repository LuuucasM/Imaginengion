const std = @import("std");
const Vec4f32 = @import("../Math/LinAlg.zig").Vec4f32;
const TextureFormat = @import("InternalFrameBuffer.zig").TextureFormat;
const glad = @import("../Core/CImports.zig").glad;

pub fn OpenGLFrameBuffer(comptime color_texture_formats: []const TextureFormat, comptime depth_texture_format: TextureFormat, comptime samples: u32, comptime is_swap_chain_target: bool) type {
    _ = is_swap_chain_target;
    return struct {
        const Self = @This();

        const MultiSampled = samples > 1;
        const GLMultiSampled = if (MultiSampled == true) glad.GL_TEXTURE_2D_MULTISAMPLE else glad.GL_TEXTURE_2D;
        const DrawBuffers = blk: {
            var buff: [color_texture_formats.len]glad.GLenum = [_]glad.GLenum{glad.GL_COLOR_ATTACHMENT0};
            for (&buff, 0..) |*ele, i| {
                ele.* += i;
            }
            break :blk buff;
        };

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
            if (width < 1 or height < 1 or width > 8192 or height > 8192) return;
            self.mWidth = width;
            self.mHeight = height;
            self.Invalidate();
        }
        pub fn GetColorAttachmentID(self: Self, attachment_index: u8) u32 {
            std.debug.assert(attachment_index < color_texture_formats.len);
            return self.mColorAttachments[attachment_index];
        }
        pub fn ClearFrameBuffer(self: Self, color: Vec4f32) void {
            _ = self;
            glad.glClearColor(color[0], color[1], color[2], color[3]);
            glad.glClear(glad.GL_COLOR_BUFFER_BIT | glad.GL_DEPTH_BUFFER_BIT);
        }
        pub fn ClearColorAttachment(self: Self, attachment_index: u32, value: u32) void {
            std.debug.assert(attachment_index < color_texture_formats.len);
            glad.glClearTexImage(self.mColorAttachments[attachment_index], 0, TextureFormatToInternalFormat(color_texture_formats[attachment_index]), glad.GL_UNSIGNED_INT, &value);
        }

        pub fn BindColorAttachment(self: Self, attachment_index: u8, slot: usize) void {
            std.debug.assert(attachment_index < color_texture_formats.len);
            glad.glBindTextureUnit(@intCast(slot), self.mColorAttachments[attachment_index]);
        }

        pub fn BindDepthAttachment(self: Self, slot: usize) void {
            glad.glBindTextureUnit(@intCast(slot), self.mDepthAttachment);
        }

        fn Create(self: *Self) void {
            glad.glCreateFramebuffers(1, &self.mBufferID);
            glad.glBindFramebuffer(glad.GL_FRAMEBUFFER, self.mBufferID);

            //color attachments
            if (color_texture_formats.len > 0) {
                glad.glCreateTextures(GLMultiSampled, color_texture_formats.len, &self.mColorAttachments[0]);
                for (color_texture_formats, 0..) |texture_format, i| {
                    glad.glBindTexture(GLMultiSampled, self.mColorAttachments[i]);
                    AttachColorTexture(self.mColorAttachments[i], texture_format, @intCast(self.mWidth), @intCast(self.mHeight), @intCast(i));
                }
            }

            //depths attachments
            if (depth_texture_format != TextureFormat.None) {
                glad.glCreateTextures(GLMultiSampled, 1, &self.mDepthAttachment);
                glad.glBindTexture(GLMultiSampled, self.mDepthAttachment);
                AttachDepthTexture(self.mDepthAttachment, depth_texture_format, @intCast(self.mWidth), @intCast(self.mHeight));
            }

            if (color_texture_formats.len == 0) {
                glad.glDrawBuffer(glad.GL_NONE);
            } else {
                glad.glDrawBuffers(@intCast(DrawBuffers.len), &DrawBuffers[0]);
            }

            std.debug.assert(glad.glCheckFramebufferStatus(glad.GL_FRAMEBUFFER) == glad.GL_FRAMEBUFFER_COMPLETE);

            glad.glBindFramebuffer(glad.GL_FRAMEBUFFER, 0);
        }

        fn AttachColorTexture(attachment_id: u32, texture_format: TextureFormat, width: usize, height: usize, index: c_uint) void {
            if (MultiSampled == true) {
                glad.glTexImage2DMultisample(glad.GL_TEXTURE_2D_MULTISAMPLE, samples, TextureFormatToInternalFormat(texture_format), @intCast(width), @intCast(height), glad.GL_FALSE);
            } else {
                glad.glTexImage2D(glad.GL_TEXTURE_2D, 0, @intCast(TextureFormatToInternalFormat(texture_format)), @intCast(width), @intCast(height), 0, TextureFormatToFormat(texture_format), TextureFormatToType(texture_format), null);

                glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_MIN_FILTER, glad.GL_LINEAR);
                glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_MAG_FILTER, glad.GL_LINEAR);
                glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_WRAP_R, glad.GL_CLAMP_TO_EDGE);
                glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_WRAP_S, glad.GL_CLAMP_TO_EDGE);
                glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_WRAP_T, glad.GL_CLAMP_TO_EDGE);
                glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_SWIZZLE_R, glad.GL_RED);
                glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_SWIZZLE_G, glad.GL_GREEN);
                glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_SWIZZLE_B, glad.GL_BLUE);
                glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_SWIZZLE_A, glad.GL_ALPHA);
            }
            glad.glFramebufferTexture2D(glad.GL_FRAMEBUFFER, @as(c_uint, @intCast(glad.GL_COLOR_ATTACHMENT0)) + index, GLMultiSampled, attachment_id, 0);
        }

        fn AttachDepthTexture(attachment_id: u32, texture_format: TextureFormat, width: usize, height: usize) void {
            if (MultiSampled == true) {
                glad.glTexImage2DMultisample(glad.GL_TEXTURE_2D_MULTISAMPLE, samples, TextureFormatToInternalFormat(texture_format), @intCast(width), @intCast(height), glad.GL_FALSE);
            } else {
                glad.glTexStorage2D(glad.GL_TEXTURE_2D, 1, TextureFormatToInternalFormat(texture_format), @intCast(width), @intCast(height));

                glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_MIN_FILTER, glad.GL_LINEAR);
                glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_MAG_FILTER, glad.GL_LINEAR);
                glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_WRAP_R, glad.GL_CLAMP_TO_EDGE);
                glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_WRAP_S, glad.GL_CLAMP_TO_EDGE);
                glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_WRAP_T, glad.GL_CLAMP_TO_EDGE);
                glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_SWIZZLE_R, glad.GL_RED);
                glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_SWIZZLE_G, glad.GL_GREEN);
                glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_SWIZZLE_B, glad.GL_BLUE);
                glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_SWIZZLE_A, glad.GL_ALPHA);
            }

            glad.glFramebufferTexture2D(glad.GL_FRAMEBUFFER, TextureFormatToFormat(texture_format), GLMultiSampled, attachment_id, 0);
        }

        fn TextureFormatToInternalFormat(format: TextureFormat) glad.GLenum {
            return switch (format) {
                .RGBA8 => glad.GL_RGBA8,
                .RGBA16F => glad.GL_RGBA16F,
                .RED_INTEGER => glad.GL_R32UI,
                .DEPTH24STENCIL8 => glad.GL_DEPTH24_STENCIL8,
                else => @panic("This texture format isnt implemented yet!"),
            };
        }
        fn TextureFormatToFormat(format: TextureFormat) glad.GLenum {
            return switch (format) {
                .RGBA8 => glad.GL_RGBA,
                .RGBA16F => glad.GL_RGBA,
                .RED_INTEGER => glad.GL_RED_INTEGER,
                .DEPTH24STENCIL8 => glad.GL_DEPTH_STENCIL_ATTACHMENT,
                else => @panic("This texture format isnt implemented yet!"),
            };
        }
        fn TextureFormatToType(format: TextureFormat) glad.GLenum {
            return switch (format) {
                .RGBA8 => glad.GL_UNSIGNED_BYTE,
                .RGBA16F => glad.GL_HALF_FLOAT,
                else => @panic("This texture format isnt implemented yet!"),
            };
        }
    };
}

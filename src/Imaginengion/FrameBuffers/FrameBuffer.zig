const std = @import("std");
const builtin = @import("builtin");
const Vec4f32 = @import("../Math/LinAlg.zig").Vec4f32;
const EngineContext = @import("../Core/EngineContext.zig");

const Impl = switch (builtin.os.tag) {
    .windows => @import("SDLFrameBuffer.zig"),
    else => @import("UnsupportedFrameBuffer.zig"),
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

pub fn FrameBuffer(comptime color_texture_formats: []const TextureFormat, comptime depth_texture_format: TextureFormat, comptime samples: usize) type {
    return struct {
        const Self = @This();
        const ImplType = Impl(color_texture_formats, depth_texture_format, samples);
        mImpl: ImplType,

        pub const empty: Self = .{
            .mImpl = .empty,
        };

        pub fn Init(self: Self, engine_context: *EngineContext, width: usize, height: usize) void {
            self.mImpl.Init(engine_context, width, height);
        }
        pub fn Deinit(self: Self, engine_context: *EngineContext) void {
            self.mImpl.Deinit(engine_context);
        }
        pub fn BeginRenderPass(self: *Self, engine_context: *EngineContext, clear_colors: [color_texture_formats.len]Vec4f32) *anyopaque {
            return self.mImpl.BeginRenderPass(engine_context, clear_colors);
        }
        pub fn EndRenderPass(self: Self, render_pass: *anyopaque) void {
            self.mImpl.EndRenderPass(render_pass);
        }
        pub fn Resize(self: *Self, engine_context: *EngineContext, width: usize, height: usize) void {
            self.mImpl.Resize(engine_context, width, height);
        }
        pub fn Invalidate(self: *Self, engine_context: *EngineContext) void {
            self.mImpl.Invalidate(engine_context);
        }
        pub fn GetColorTexture(self: Self, attachment_index: usize) *anyopaque {
            return self.mImpl.GetColorTexture(attachment_index);
        }
        pub fn GetColorSampler(self: Self, attachment_index: usize) *anyopaque {
            return self.mImpl.GetColorSampler(attachment_index);
        }
        pub fn GetDepthTexture(self: Self) *anyopaque {
            return self.mImpl.GetDepthTexture();
        }
        pub fn BindColorAttachment(self: Self, render_pass: *anyopaque, attachment_index: usize, slot: u32) void {
            self.mImpl.BindColorAttachment(render_pass, attachment_index, slot);
        }
        pub fn BindDepthAttachment(self: Self, render_pass: *anyopaque, slot: u32) void {
            self.mImpl.BindDepthAttachment(render_pass, slot);
        }
    };
}

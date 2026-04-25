const std = @import("std");
const builtin = @import("builtin");
const Vec4f32 = @import("../Math/LinAlg.zig").Vec4f32;
const TextureFormat = @import("../Assets/Assets.zig").Texture2D.TextureFormat;
const Texture2D = @import("../Assets/Assets.zig").Texture2D;
const EngineContext = @import("../Core/EngineContext.zig");

pub fn FrameBuffer(comptime color_texture_formats: []const TextureFormat, comptime depth_texture_format: TextureFormat, comptime samples: usize) type {
    return struct {
        const Self = @This();
        const Impl = switch (builtin.os.tag) {
            .windows => @import("SDLFrameBuffer.zig"),
            else => @compileError("This cant happen yet!"),
        };
        const ImplType = Impl.FrameBuffer(color_texture_formats, depth_texture_format, samples);
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
        pub fn GetDepthTexture(self: Self) *anyopaque {
            return self.mImpl.GetDepthTexture();
        }
        pub fn GetWidth(self: Self) usize {
            return self.mImpl.GetWidth();
        }
        pub fn GetHeight(self: Self) usize {
            return self.mImpl.GetHeight();
        }
    };
}

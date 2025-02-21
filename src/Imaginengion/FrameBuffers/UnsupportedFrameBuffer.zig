const std = @import("std");
const builtin = @import("builtin");
const TextureFormat = @import("InternalFrameBuffer.zig").TextureFormat;

pub fn OpenGLFrameBuffer(comptime color_texture_formats: []const TextureFormat, comptime depth_texture_format: TextureFormat, comptime samples: u32, comptime is_swap_chain_target: bool) type {
    _ = color_texture_formats;
    _ = depth_texture_format;
    _ = samples;
    _ = is_swap_chain_target;
    Unsupported();
}

fn Unsupported() noreturn {
    @compileError("Unsupported operating system: " ++ @tagName(builtin.os.tag) ++ " in Texture2D\n");
}

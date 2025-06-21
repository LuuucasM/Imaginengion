const std = @import("std");
const builtin = @import("builtin");
const SSBO = @This();

const Impl = switch (builtin.os.tag) {
    .windows => @import("OpenGLSSBO.zig"),
    else => @import("UnsupportedSSBO.zig"),
};

mImpl: Impl,

pub fn Init(size: usize) SSBO {
    return SSBO{
        .mImpl = Impl.Init(size),
    };
}

pub fn Deinit(self: SSBO) void {
    self.mImpl.Deinit();
}

pub fn Bind(self: *SSBO, binding: usize) void {
    self.mImpl.Bind(binding);
}

pub fn Unbind(self: SSBO) void {
    self.mImpl.Unbind();
}

pub fn SetData(self: SSBO, data: *anyopaque, size: usize, offset: u32) void {
    self.mImpl.SetData(data, size, offset);
}

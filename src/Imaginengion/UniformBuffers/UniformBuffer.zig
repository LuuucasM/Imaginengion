const builtin = @import("builtin");
const Tracy = @import("../Core/Tracy.zig");

const Impl = switch (builtin.os.tag) {
    .windows => @import("OpenGLUniformBuffer.zig"),
    else => @import("UnsupportedUniformBuffer.zig"),
};

const UniformBuffer = @This();

mImpl: Impl,

pub fn Init(size: u32) UniformBuffer {
    return UniformBuffer{
        .mImpl = Impl.Init(size),
    };
}

pub fn Bind(self: *UniformBuffer, binding: usize) void {
    const zone = Tracy.ZoneInit("UniformBuffer Bind", @src());
    defer zone.Deinit();
    self.mImpl.Bind(binding);
}

pub fn Deinit(self: UniformBuffer) void {
    self.mImpl.Deinit();
}

pub fn SetData(self: UniformBuffer, data: *anyopaque, size: u32, offset: u32) void {
    self.mImpl.SetData(data, size, offset);
}

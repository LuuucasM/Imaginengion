const builtin = @import("builtin");

const Impl = switch (builtin.os.tag) {
    .windows => @import("OpenGLIndexBuffer.zig"),
    else => @import("UnsupportedVertexBuffer.zig"),
};

const IndexBuffer = @This();

mImpl: Impl,

pub fn Init(indices: []u32, count: usize) IndexBuffer {
    return IndexBuffer{
        .mImpl = Impl.Init(indices, count),
    };
}

pub fn Deinit(self: IndexBuffer) void {
    self.mImpl.Deinit();
}

pub fn Bind(self: IndexBuffer) void {
    self.mImpl.Bind();
}

pub fn Unbind(self: IndexBuffer) void {
    self.mImpl.Unbind();
}

pub fn GetCount(self: IndexBuffer) usize {
    return self.GetCount();
}

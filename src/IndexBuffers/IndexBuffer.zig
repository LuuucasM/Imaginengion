const builtin = @import("builtin");

const Impl = switch (builtin.os.tag) {
    .windows => @import("OpenGLIndexBuffer.zig"),
    else => @import("UnsupportedVertexBuffer.zig"),
};

const IndexBuffer = @This();

mCount: u32,
mBufferID: c_uint,

pub fn Init(indices: []u32, count: u32) IndexBuffer {
    const new_ib = IndexBuffer{
        .mCount = count,
        .mBufferID = 0,
    };
    Impl.Init(&new_ib.mBufferID, indices, count);
}

pub fn Deinit(self: IndexBuffer) void {
    Impl.Deinit(&self.mBufferID);
}

pub fn Bind(self: IndexBuffer) void {
    Impl.Bind(self.mBufferID);
}

pub fn Unbind(self: IndexBuffer) void {
    _ = self;
    Impl.Unbind();
}

pub fn GetCount(self: IndexBuffer) u32 {
    return self.mCount;
}

const VertexArray = @import("../VertexArrays/VertexArray.zig");
const builtin = @import("builtin");

const Impl = switch (builtin.os.tag) {
    .windows => @import("OpenGLContext.zig"),
    else => @import("UnsupportedContext.zig"),
};

const RenderContext = @This();

mImpl: Impl,

pub fn Init() RenderContext {
    return RenderContext{
        .mImpl = Impl.Init(),
    };
}

pub fn SwapBuffers(self: RenderContext) void {
    self.mImpl.SwapBuffers();
}

pub fn SetELineThickness(self: RenderContext, thickness: f32) void {
    self.mImpl.SetELineThickness(thickness);
}

pub fn GetMaxTextureImageSlots(self: RenderContext) usize {
    return self.mImpl.GetMaxTextureImageSlots();
}

pub fn DrawIndexed(self: RenderContext, vertex_array: VertexArray, index_count: usize) void {
    self.mImpl.DrawIndexed(vertex_array, index_count);
}

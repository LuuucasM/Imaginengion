const builtin = @import("builtin");

const Impl = switch (builtin.os.tag) {
    .windows => @import("OpenGLContext.zig"),
    else => @import("UnsupportedContext.zig"),
};

const RenderContext = @This();

_Impl: Impl,

pub fn Init() RenderContext {
    return RenderContext{
        ._Impl = Impl.Init(),
    };
}

pub fn SwapBuffers(self: RenderContext) void {
    self._Impl.SwapBuffers();
}

pub fn GetMaxTextureImageSlots(self: RenderContext) usize {
    return self._Impl.GetMaxTextureImageSlots();
}

pub fn DrawIndexed(vertex_array: VertexArray, index_count: usize) void {}

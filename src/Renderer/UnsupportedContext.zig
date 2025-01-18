const UnsupportedContext = @This();
const VertexArray = @import("../VertexArrays/VertexArray.zig");

pub fn Init() UnsupportedContext {
    Unsupported();
}

pub fn SwapBuffers(self: UnsupportedContext) void {
    _ = self;
    Unsupported();
}

pub fn GetMaxTextureImageSlots(self: UnsupportedContext) u32 {
    _ = self;
    Unsupported();
}

pub fn DrawIndexed(self: UnsupportedContext, vertex_array: VertexArray, index_count: usize) void {
    _ = self;
    _ = vertex_array;
    _ = index_count;
    Unsupported();
}

fn Unsupported() noreturn {
    @compileError("Unsupported OS for RenderContext");
}

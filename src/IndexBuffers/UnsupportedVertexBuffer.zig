const UnsupportedVertexBuffer = @This();

pub fn Init(indices: []u32, count: usize) UnsupportedVertexBuffer {
    _ = indices;
    _ = count;
    Unsupported();
    return UnsupportedVertexBuffer{};
}

pub fn Deinit(self: UnsupportedVertexBuffer) void {
    _ = self;
    Unsupported();
}

pub fn Bind(self: UnsupportedVertexBuffer) void {
    _ = self;
    Unsupported();
}

pub fn Unbind(self: UnsupportedVertexBuffer) void {
    _ = self;
    Unsupported();
}

pub fn GetCount(self: UnsupportedVertexBuffer) usize {
    _ = self;
    Unsupported();
}

fn Unsupported() noreturn {
    @compileError("Unsupported OS for RenderContext");
}

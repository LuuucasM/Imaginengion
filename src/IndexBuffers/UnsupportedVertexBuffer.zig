const UnsupportedVertexBuffer = @This();

pub fn Init(indices: []u32, count: u32) UnsupportedVertexBuffer {
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

pub fn GetCount(self: UnsupportedVertexBuffer) u32 {
    _ = self;
    Unsupported();
}

fn Unsupported() noreturn {
    @compileError("Unsupported OS for RenderContext");
}

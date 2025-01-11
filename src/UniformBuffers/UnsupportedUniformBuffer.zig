const UnsupportedUniformBuffer = @This();

pub fn Init(size: u32, binding: u32) UnsupportedUniformBuffer {
    _ = size;
    _ = binding;
    Unsupported();
    return UnsupportedUniformBuffer{};
}

pub fn Deinit(self: UnsupportedUniformBuffer) void {
    _ = self;
    Unsupported();
}

pub fn SetData(self: UnsupportedUniformBuffer, data: *anyopaque, size: u32, offset: u32) void {
    _ = self;
    _ = data;
    _ = size;
    _ = offset;
    Unsupported();
}

fn Unsupported() noreturn {
    @compileError("Unsupported OS for RenderContext");
}

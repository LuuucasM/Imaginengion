const UnsupportedSSBO = @This();

pub fn Init(_: usize) UnsupportedSSBO {
    Unsupported();
}

pub fn Deinit(_: UnsupportedSSBO) void {
    Unsupported();
}

pub fn Bind(_: UnsupportedSSBO, _: usize) void {
    Unsupported();
}

pub fn Unbind(_: UnsupportedSSBO) void {
    Unsupported();
}

pub fn SetData(_: UnsupportedSSBO, _: *anyopaque, _: usize, _: u32) void {
    Unsupported();
}

fn Unsupported() noreturn {
    @compileError("Unsupported OS for RenderContext");
}

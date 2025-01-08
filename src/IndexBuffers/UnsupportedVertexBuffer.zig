const UnsupportedVertexBuffer = @This();

pub fn Init(buffer_id_out: *c_uint, indices: []u32, count: u32) void {
    _ = buffer_id_out;
    _ = indices;
    _ = count;
    Unsupported();
}

pub fn Bind(buffer_id: c_uint) void {
    _ = buffer_id;
    Unsupported();
}

pub fn Unbind() void {
    Unsupported();
}

pub fn Deinit(buffer_id_out: *c_uint) void {
    _ = buffer_id_out;
    Unsupported();
}

fn Unsupported() noreturn {
    @compileError("Unsupported OS for RenderContext");
}

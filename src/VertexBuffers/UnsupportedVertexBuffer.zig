const std = @import("std");

const UnsupportedVertexBuffer = @This();

pub fn Init(size: usize, buffer_id_out: *c_uint) void {
    _ = size;
    _ = buffer_id_out;
    Unsupported();
}

pub fn Deinit(buffer_id_out: c_uint) void {
    _ = buffer_id_out;
    Unsupported();
}

pub fn Bind(buffer_id_out: c_uint) void {
    _ = buffer_id_out;
    Unsupported();
}

pub fn Unbind() void {
    Unsupported();
}

pub fn SetData(buffer_id_out: c_uint, data: *anyopaque, size: usize) void {
    _ = buffer_id_out;
    _ = data;
    _ = size;
    Unsupported();
}

fn Unsupported() noreturn {
    @compileError("Unsupported OS for RenderContext");
}

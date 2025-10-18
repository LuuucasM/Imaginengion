const std = @import("std");
const NullAudioBuffer = @This();

pub fn Init(_: std.mem.Allocator, _: std.fs.File) !NullAudioBuffer {
    Unsupported();
}

pub fn Deinit(_: *NullAudioBuffer) !void {
    Unsupported();
}

fn Unsupported() noreturn {
    @compileError("Unsupported audio buffer!\n");
}

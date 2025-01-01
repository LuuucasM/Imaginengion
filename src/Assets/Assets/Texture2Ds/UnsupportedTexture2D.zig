const builtin = @import("builtin");
const UnsupportedTexture2D = @This();

pub fn Init(path: []const u8) !UnsupportedTexture2D {
    _ = path;
    Unsupported();
}
pub fn GetWidth(self: UnsupportedTexture2D) u32 {
    _ = self;
    Unsupported();
}
pub fn GetHeight(self: UnsupportedTexture2D) u32 {
    _ = self;
    Unsupported();
}
pub fn GetID(self: UnsupportedTexture2D) u32 {
    _ = self;
    Unsupported();
}
pub fn UpdateData(self: UnsupportedTexture2D, width: u32, height: u32, data: *anyopaque, size: usize) void {
    _ = self;
    _ = width;
    _ = height;
    _ = data;
    _ = size;
    Unsupported();
}
pub fn UpdateDataPath(self: UnsupportedTexture2D, path: []const u8) void {
    _ = self;
    _ = path;
    Unsupported();
}
pub fn Bind(self: UnsupportedTexture2D, slot: u32) void {
    _ = self;
    _ = slot;
    Unsupported();
}
pub fn Unbind(self: UnsupportedTexture2D, slot: u32) void {
    _ = self;
    _ = slot;
    Unsupported();
}

fn Unsupported() noreturn {
    @compileError("Unsupported operating system: " ++ @tagName(builtin.os.tag) ++ " in Texture2D\n");
}

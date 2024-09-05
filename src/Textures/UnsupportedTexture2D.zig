pub fn GetWidth(self: Texture) u32 {
    _ = self;
    Unsupported();
}
pub fn GetHeight(self: Texture) u32 {
    _ = self;
    Unsupported();
}
pub fn GetID(self: Texture) u32 {
    _ = self;
    Unsupported();
}
pub fn SetData(self: Texture, data: *anyopaque, size: usize) void {
    _ = self;
    _ = data;
    _ = size;
    Unsupported();
}
pub fn Bind(self: Texture, slot: u32) void {
    _ = self;
    _ = slot;
    Unsupported();
}
pub fn Unbind(self: Texture, slot: u32) void {
    _ = self;
    _ = slot;
    Unsupported();
}

fn Unsupported() noreturn {
    @compileError("Unsupported operating system: " ++ @tagName(builtin.os.tag) ++ " in Texture2D\n");
}
